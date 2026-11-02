import UIKit
import WebKit

/// Native note chrome + miolo WKWebView (`/native-editor` + `v2n` bridge).
final class NoteDetailViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate {
    private let noteId: String
    private var note: NativeAPIClient.NoteDocument
    private var speakers: [NativeAPIClient.SpeakerDTO] = []
    private var webView: WKWebView!
    private var saveWork: DispatchWorkItem?
    private var editorReady = false
    private let statusLabel = UILabel()

    init(noteId: String, initial: NativeAPIClient.NoteDocument?) {
        self.noteId = noteId
        self.note = initial ?? NativeAPIClient.emptyNote(id: noteId)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        updateTitle()

        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), style: .plain, target: self, action: #selector(openMore)),
        ]

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .preferredFont(forTextStyle: .caption2)
        statusLabel.textColor = .secondaryLabel
        statusLabel.text = "A carregar…"
        view.addSubview(statusLabel)

        let userContent = WKUserContentController()
        userContent.add(self, name: "v2n")
        injectBearer(into: userContent)
        let config = WKWebViewConfiguration()
        config.userContentController = userContent
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            statusLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),

            webView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 4),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let url = NativeAPIClient.baseURL.appendingPathComponent("native-editor")
        webView.load(URLRequest(url: url))
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(noteDidChangeExternally(_:)),
            name: .nativeNoteDidChange,
            object: nil
        )
        Task { await refreshFromAPI() }
    }

    @objc private func noteDidChangeExternally(_ note: Notification) {
        guard let id = note.object as? String, id == noteId else { return }
        Task { await refreshFromAPI() }
    }

    deinit {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "v2n")
        saveWork?.cancel()
    }

    private func injectBearer(into userContent: WKUserContentController) {
        guard let token = KeychainStore.bearerToken(), !token.isEmpty else { return }
        let escaped = token
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let js = """
        try {
          window.localStorage.setItem('grok-auth.bearer-token', '\(escaped)');
          window.sessionStorage.setItem('grok-auth.bearer-token', '\(escaped)');
        } catch (e) {}
        """
        userContent.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }

    private func updateTitle() {
        let t = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        title = t.isEmpty ? "Reunião" : t
    }

    private func refreshFromAPI() async {
        do {
            let packed = try await NativeAPIClient.getNote(id: noteId)
            await MainActor.run {
                self.note = packed.note
                self.speakers = packed.speakers
                self.updateTitle()
                self.statusLabel.text = "Nota sincronizada"
                if self.editorReady { self.pushNoteToEditor() }
            }
        } catch {
            await MainActor.run {
                self.statusLabel.text = "Cache local · \(error.localizedDescription)"
                if self.editorReady { self.pushNoteToEditor() }
            }
        }
    }

    private func pushNoteToEditor() {
        guard let data = try? JSONEncoder().encode(note),
              let noteJSON = String(data: data, encoding: .utf8)
        else { return }
        let speakersJSON: String
        if let sData = try? JSONEncoder().encode(speakers),
           let s = String(data: sData, encoding: .utf8)
        {
            speakersJSON = s
        } else {
            speakersJSON = "[]"
        }
        let js = """
        (function(){
          var msg = { type: 'loadNote', note: \(noteJSON), speakers: \(speakersJSON), readOnly: false };
          if (window.__V2N_EDITOR_LOAD__) { window.__V2N_EDITOR_LOAD__(msg); }
          else { window.postMessage(msg, '*'); }
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "v2n" else { return }
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            editorReady = true
            statusLabel.text = "Editor pronto"
            pushNoteToEditor()
        case "noteChanged":
            if let noteObj = body["note"] {
                applyEditorNote(noteObj)
            }
        case "error":
            statusLabel.text = "Editor: \(body["message"] as? String ?? "erro")"
        case "requestSpeaker":
            openSpeakerPicker()
        default:
            break
        }
    }

    private func applyEditorNote(_ raw: Any) {
        guard JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw),
              let decoded = try? JSONDecoder().decode(NativeAPIClient.NoteDocument.self, from: data)
        else { return }
        // Preserve chrome fields the miolo may not edit.
        var next = decoded
        next.id = noteId
        next.title = note.title
        next.happenedAt = note.happenedAt
        next.tags = note.tags
        next.noteSpeakerId = note.noteSpeakerId
        next.visibility = note.visibility
        next.schemaVersion = 1
        note = next
        LocalNoteCache.upsertNote(note)
        scheduleSave()
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { await self.persist() }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
        statusLabel.text = "A guardar…"
    }

    private func persist() async {
        do {
            let saved = try await NativeAPIClient.upsertNote(note)
            await MainActor.run {
                self.note = saved
                self.statusLabel.text = "Guardado"
            }
        } catch {
            await MainActor.run {
                self.statusLabel.text = "Guardado localmente · \(error.localizedDescription)"
            }
        }
    }

    @objc private func openMore() {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Configurações", style: .default) { [weak self] _ in
            self?.openSettings()
        })
        sheet.addAction(UIAlertAction(title: "Speakers…", style: .default) { [weak self] _ in
            self?.openSpeakerPicker()
        })
        if NativeAPIClient.hasBearer {
            sheet.addAction(UIAlertAction(title: "Mover para grupo…", style: .default) { [weak self] _ in
                self?.moveToGroup()
            })
        }
        sheet.addAction(UIAlertAction(title: "Partilhar", style: .default) { [weak self] _ in
            self?.shareNote()
        })
        sheet.addAction(UIAlertAction(title: "Apagar nota", style: .destructive) { [weak self] _ in
            self?.confirmDelete()
        })
        sheet.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.barButtonItem = navigationItem.rightBarButtonItem
        }
        present(sheet, animated: true)
    }

    private func moveToGroup() {
        Task { @MainActor in
            do {
                // Persist latest chrome/body before publishing the association.
                _ = try await NativeAPIClient.upsertNote(note)
                let groups = try await NativeAPIClient.listGroupsForNote(noteId: noteId)
                let eligible = groups.filter { $0.canPost }
                guard !eligible.isEmpty else {
                    let empty = UIAlertController(
                        title: "Sem grupos",
                        message: "Cria ou junta-te a um grupo no separador Grupos.",
                        preferredStyle: .alert
                    )
                    empty.addAction(UIAlertAction(title: "OK", style: .default))
                    present(empty, animated: true)
                    return
                }
                let sheet = UIAlertController(title: "Mover para grupo", message: nil, preferredStyle: .actionSheet)
                for group in eligible {
                    let title = (group.published == true) ? "✓ \(group.name)" : group.name
                    sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                        self?.togglePublish(group)
                    })
                }
                sheet.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
                if let pop = sheet.popoverPresentationController {
                    pop.barButtonItem = navigationItem.rightBarButtonItem
                }
                present(sheet, animated: true)
            } catch {
                let err = UIAlertController(title: "Erro", message: error.localizedDescription, preferredStyle: .alert)
                err.addAction(UIAlertAction(title: "OK", style: .default))
                present(err, animated: true)
            }
        }
    }

    private func togglePublish(_ group: NativeAPIClient.GroupDTO) {
        Task { @MainActor in
            do {
                if group.published == true {
                    try await NativeAPIClient.unpublishNote(noteId: noteId, fromGroupId: group.id)
                    statusLabel.text = "Retirada de «\(group.name)»"
                } else {
                    try await NativeAPIClient.publishNote(noteId: noteId, toGroupId: group.id)
                    statusLabel.text = "Movida para «\(group.name)»"
                }
            } catch {
                let err = UIAlertController(title: "Erro", message: error.localizedDescription, preferredStyle: .alert)
                err.addAction(UIAlertAction(title: "OK", style: .default))
                present(err, animated: true)
            }
        }
    }

    private func openSettings() {
        let settings = NoteSettingsViewController(note: note, speakers: speakers) { [weak self] updated in
            guard let self else { return }
            self.note = updated
            self.updateTitle()
            LocalNoteCache.upsertNote(updated)
            self.scheduleSave()
            if self.editorReady { self.pushNoteToEditor() }
        }
        let nav = UINavigationController(rootViewController: settings)
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(nav, animated: true)
    }

    private func openSpeakerPicker() {
        let picker = SpeakerPickerViewController(mode: .pick(selectedId: note.noteSpeakerId), onPicked: { [weak self] speakerId in
            guard let self else { return }
            self.note.noteSpeakerId = speakerId
            LocalNoteCache.upsertNote(self.note)
            self.scheduleSave()
        })
        let nav = UINavigationController(rootViewController: picker)
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(nav, animated: true)
    }

    private func shareNote() {
        let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Reunião" : note.title
        let url = NativeAPIClient.baseURL.appendingPathComponent("n/\(note.id)")
        let vc = UIActivityViewController(activityItems: [title, note.preview, url], applicationActivities: nil)
        if let pop = vc.popoverPresentationController {
            pop.barButtonItem = navigationItem.rightBarButtonItem
        }
        present(vc, animated: true)
    }

    private func confirmDelete() {
        let alert = UIAlertController(title: nil, message: "Apagar esta nota?", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
        alert.addAction(UIAlertAction(title: "Apagar nota", style: .destructive) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                do {
                    try await NativeAPIClient.deleteNote(id: self.noteId)
                    self.navigationController?.popViewController(animated: true)
                } catch {
                    let err = UIAlertController(title: "Erro", message: error.localizedDescription, preferredStyle: .alert)
                    err.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(err, animated: true)
                }
            }
        })
        if let pop = alert.popoverPresentationController {
            pop.barButtonItem = navigationItem.rightBarButtonItem
        }
        present(alert, animated: true)
    }
}
