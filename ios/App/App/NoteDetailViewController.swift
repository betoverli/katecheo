import UIKit

/// Native note chrome + isolated miolo (`NoteMioloEditorView`). No site shell.
final class NoteDetailViewController: UIViewController, NoteMioloEditorViewDelegate {
    private let noteId: String
    private var note: NativeAPIClient.NoteDocument
    private var speakers: [NativeAPIClient.SpeakerDTO] = []
    private let editor = NoteMioloEditorView()
    private var saveWork: DispatchWorkItem?
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
        statusLabel.text = "Carregando…"
        view.addSubview(statusLabel)

        editor.delegate = self
        editor.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(editor)

        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            statusLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),

            editor.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 4),
            editor.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            editor.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            editor.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        editor.loadEditor()
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
        saveWork?.cancel()
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
                if self.editor.isReady { self.editor.pushNote(self.note, speakers: self.speakers) }
            }
        } catch {
            await MainActor.run {
                self.statusLabel.text = "Cache local · \(error.localizedDescription)"
                if self.editor.isReady { self.editor.pushNote(self.note, speakers: self.speakers) }
            }
        }
    }

    // MARK: - NoteMioloEditorViewDelegate

    func noteMioloEditorDidBecomeReady(_ editor: NoteMioloEditorView) {
        statusLabel.text = "Editor pronto"
        editor.pushNote(note, speakers: speakers)
    }

    func noteMioloEditor(_ editor: NoteMioloEditorView, didChangeNote raw: Any) {
        applyEditorNote(raw)
    }

    func noteMioloEditor(_ editor: NoteMioloEditorView, didFail message: String) {
        statusLabel.text = "Editor: \(message)"
    }

    func noteMioloEditorDidRequestSpeaker(_ editor: NoteMioloEditorView) {
        openSpeakerPicker()
    }

    private func applyEditorNote(_ raw: Any) {
        guard JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw),
              let decoded = try? JSONDecoder().decode(NativeAPIClient.NoteDocument.self, from: data)
        else { return }
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
        statusLabel.text = "Salvando…"
    }

    private func persist() async {
        do {
            let saved = try await NativeAPIClient.upsertNote(note)
            await MainActor.run {
                self.note = saved
                self.statusLabel.text = "Salvo"
            }
        } catch NativeAPIClient.APIError.unauthorized {
            NativeOutbox.enqueueNoteUpsert(note)
            await MainActor.run {
                self.statusLabel.text = "Sessão expirada — alteração guardada no aparelho."
            }
        } catch {
            NativeOutbox.enqueueNoteUpsert(note)
            await MainActor.run {
                self.statusLabel.text = "Salvo no aparelho — sincroniza quando houver rede."
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
        sheet.addAction(UIAlertAction(title: "Compartilhar", style: .default) { [weak self] _ in
            self?.shareNote()
        })
        sheet.addAction(UIAlertAction(title: "Excluir nota", style: .destructive) { [weak self] _ in
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
                _ = try await NativeAPIClient.upsertNote(note)
                let groups = try await NativeAPIClient.listGroupsForNote(noteId: noteId)
                let eligible = groups.filter { $0.canPost }
                guard !eligible.isEmpty else {
                    let empty = UIAlertController(
                        title: "Sem grupos",
                        message: "Crie ou entre em um grupo na aba Grupos.",
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
            if self.editor.isReady { self.editor.pushNote(self.note, speakers: self.speakers) }
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
        let alert = UIAlertController(title: nil, message: "Excluir esta nota?", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
        alert.addAction(UIAlertAction(title: "Excluir nota", style: .destructive) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                do {
                    try await NativeAPIClient.deleteNote(id: self.noteId)
                    self.navigationController?.popViewController(animated: true)
                } catch NativeAPIClient.APIError.unauthorized {
                    LocalNoteCache.removeNote(id: self.noteId)
                    NativeOutbox.enqueueNoteDelete(id: self.noteId)
                    self.navigationController?.popViewController(animated: true)
                } catch {
                    LocalNoteCache.removeNote(id: self.noteId)
                    NativeOutbox.enqueueNoteDelete(id: self.noteId)
                    self.navigationController?.popViewController(animated: true)
                }
            }
        })
        if let pop = alert.popoverPresentationController {
            pop.barButtonItem = navigationItem.rightBarButtonItem
        }
        present(alert, animated: true)
    }
}
