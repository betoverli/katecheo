import UIKit

/// Native note chrome + native miolo (`NativeNoteEditorView`).
final class NoteDetailViewController: UIViewController, NativeNoteEditorViewDelegate {
    private let noteId: String
    private var note: NativeAPIClient.NoteDocument
    private var speakers: [NativeAPIClient.SpeakerDTO] = []
    private let editor = NativeNoteEditorView()
    private var saveWork: DispatchWorkItem?
    private let statusLabel = UILabel()
    private let speakerChip = UIButton(type: .system)
    private let speakerChipRemove = UIButton(type: .system)
    private let speakerChipRow = UIStackView()

    init(noteId: String, initial: NativeAPIClient.NoteDocument?) {
        self.noteId = noteId
        self.note = initial ?? NativeAPIClient.emptyNote(id: noteId)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        V2NChrome.styleCanvas(view)
        // Title lives in the editor body (first line) — keep the nav bar clear (matches original web editor).
        title = nil
        navigationItem.title = nil
        navigationItem.largeTitleDisplayMode = .never

        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), style: .plain, target: self, action: #selector(openMore)),
        ]
        navigationItem.rightBarButtonItem?.accessibilityLabel = String(localized: "Mais opções da nota")

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = V2NDesign.caption()
        statusLabel.textColor = .secondaryLabel
        statusLabel.text = String(localized: "Carregando…")
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.accessibilityLabel = String(localized: "Status da nota")
        view.addSubview(statusLabel)

        speakerChipRow.axis = .horizontal
        speakerChipRow.spacing = V2NDesign.Space.xxs
        speakerChipRow.alignment = .center
        speakerChipRow.translatesAutoresizingMaskIntoConstraints = false
        speakerChipRow.isHidden = true

        var chipConfig = UIButton.Configuration.filled()
        chipConfig.cornerStyle = .capsule
        chipConfig.baseBackgroundColor = V2NDesign.surface.withAlphaComponent(0.7)
        chipConfig.baseForegroundColor = .secondaryLabel
        chipConfig.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        chipConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var out = incoming
            out.font = V2NDesign.preferred(.subheadline, weight: .medium)
            return out
        }
        speakerChip.configuration = chipConfig
        speakerChip.addTarget(self, action: #selector(editWholeSpeaker), for: .touchUpInside)
        speakerChip.accessibilityLabel = String(localized: "Speaker da nota")

        speakerChipRemove.setTitle("×", for: .normal)
        speakerChipRemove.titleLabel?.font = V2NDesign.preferred(.title2, weight: .regular)
        speakerChipRemove.setTitleColor(.secondaryLabel, for: .normal)
        speakerChipRemove.addTarget(self, action: #selector(clearWholeSpeaker), for: .touchUpInside)
        speakerChipRemove.accessibilityLabel = String(localized: "Remover speaker")
        speakerChipRemove.widthAnchor.constraint(equalToConstant: 44).isActive = true
        speakerChipRemove.heightAnchor.constraint(equalToConstant: 44).isActive = true

        speakerChipRow.addArrangedSubview(speakerChip)
        speakerChipRow.addArrangedSubview(speakerChipRemove)
        view.addSubview(speakerChipRow)

        editor.delegate = self
        editor.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(editor)

        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: V2NDesign.Space.xxs),
            statusLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),

            speakerChipRow.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: V2NDesign.Space.xs),
            speakerChipRow.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            speakerChipRow.trailingAnchor.constraint(lessThanOrEqualTo: view.layoutMarginsGuide.trailingAnchor),

            editor.topAnchor.constraint(equalTo: speakerChipRow.bottomAnchor, constant: V2NDesign.Space.xxs),
            editor.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            editor.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            editor.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        editor.pushNote(note, speakers: speakers)
        refreshSpeakerChip()
        statusLabel.text = String(localized: "Editor nativo")
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
        // Do not mirror the note title into the navigation bar (duplicates the body title).
        title = nil
        navigationItem.title = nil
    }

    private func refreshFromAPI() async {
        do {
            let packed = try await NativeAPIClient.getNote(id: noteId)
            await MainActor.run {
                self.note = packed.note
                self.speakers = packed.speakers
                self.updateTitle()
                self.statusLabel.text = String(localized: "Nota sincronizada")
                self.editor.pushNote(self.note, speakers: self.speakers)
                self.refreshSpeakerChip()
            }
        } catch {
            await MainActor.run {
                self.statusLabel.text = String(localized: "Cache local · \(error.localizedDescription)")
                self.editor.pushNote(self.note, speakers: self.speakers)
                self.refreshSpeakerChip()
            }
        }
    }

    private func refreshSpeakerChip() {
        guard let speakerId = note.noteSpeakerId,
              let speaker = speakers.first(where: { $0.id == speakerId })
        else {
            speakerChipRow.isHidden = true
            return
        }
        speakerChipRow.isHidden = false
        var config = speakerChip.configuration ?? .filled()
        config.title = speaker.name
        config.image = UIImage(systemName: "circle.fill")
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 8, weight: .bold)
        config.imagePadding = 8
        if let color = UIColor(v2nHex: speaker.color) {
            config.imageColorTransformer = UIConfigurationColorTransformer { _ in color }
        }
        speakerChip.configuration = config
    }

    @objc private func editWholeSpeaker() {
        openSpeakerPicker(forSection: false)
    }

    @objc private func clearWholeSpeaker() {
        note.noteSpeakerId = nil
        refreshSpeakerChip()
        LocalNoteCache.upsertNote(note)
        scheduleSave()
    }

    // MARK: - NativeNoteEditorViewDelegate

    func nativeNoteEditorDidChange(_ editor: NativeNoteEditorView, document: NativeAPIClient.NoteDocument) {
        var next = document
        next.id = noteId
        next.happenedAt = note.happenedAt
        next.tags = note.tags
        next.noteSpeakerId = note.noteSpeakerId
        next.visibility = note.visibility
        next.schemaVersion = 1
        // Title comes from the first line of the editor.
        note = next
        updateTitle()
        LocalNoteCache.upsertNote(note)
        scheduleSave()
    }

    func nativeNoteEditor(_ editor: NativeNoteEditorView, openBibleRef ref: NoteDocumentCodec.BibleRefPayload) {
        Task { @MainActor in
            do {
                let prefs = try? await NativeAPIClient.getPrefs()
                let passage = NativeAPIClient.PassageDTO(
                    bookId: ref.bookId,
                    chapter: ref.chapter,
                    verseStart: ref.verseStart,
                    verseEnd: ref.verseEnd
                )
                let link = try await NativeAPIClient.resolveBibleLink(
                    passage: passage,
                    appId: prefs?.appId,
                    translationId: prefs?.translationId,
                    preferNative: prefs?.preferNative
                )
                guard let url = URL(string: link.url) else {
                    statusLabel.text = String(localized: "Link da Bíblia indisponível")
                    return
                }
                await UIApplication.shared.open(url)
            } catch {
                statusLabel.text = String(localized: "Não abriu a Bíblia: \(error.localizedDescription)")
            }
        }
    }

    func nativeNoteEditorRequestInsertBibleRef(_ editor: NativeNoteEditorView) {
        let picker = BibleRefInsertPicker { [weak self] ref in
            self?.editor.insertBibleRef(ref)
        }
        let nav = UINavigationController(rootViewController: picker)
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        present(nav, animated: true)
    }

    func nativeNoteEditorRequestSpeaker(_ editor: NativeNoteEditorView) {
        openSpeakerPicker(forSection: true)
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { await self.persist() }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
        statusLabel.text = String(localized: "Salvando…")
    }

    private func persist() async {
        do {
            let saved = try await NativeAPIClient.upsertNote(note)
            await MainActor.run {
                self.note = saved
                self.statusLabel.text = String(localized: "Salvo")
            }
        } catch NativeAPIClient.APIError.unauthorized {
            NativeOutbox.enqueueNoteUpsert(note)
            await MainActor.run {
                self.statusLabel.text = String(localized: "Sessão expirada — alteração guardada no aparelho.")
            }
        } catch {
            NativeOutbox.enqueueNoteUpsert(note)
            await MainActor.run {
                self.statusLabel.text = String(localized: "Salvo no aparelho — sincroniza quando houver rede.")
            }
        }
    }

    @objc private func openMore() {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: String(localized: "Configurações"), style: .default) { [weak self] _ in
            self?.openSettings()
        })
        sheet.addAction(UIAlertAction(title: String(localized: "Speakers…"), style: .default) { [weak self] _ in
            self?.openSpeakerPicker(forSection: false)
        })
        if NativeAPIClient.hasBearer {
            sheet.addAction(UIAlertAction(title: String(localized: "Mover para grupo…"), style: .default) { [weak self] _ in
                self?.moveToGroup()
            })
        }
        sheet.addAction(UIAlertAction(title: String(localized: "Compartilhar"), style: .default) { [weak self] _ in
            self?.shareNote()
        })
        sheet.addAction(UIAlertAction(title: String(localized: "Excluir nota"), style: .destructive) { [weak self] _ in
            self?.confirmDelete()
        })
        sheet.addAction(UIAlertAction(title: String(localized: "Cancelar"), style: .cancel))
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
                        title: String(localized: "Sem grupos"),
                        message: String(localized: "Crie ou entre em um grupo na aba Grupos."),
                        preferredStyle: .alert
                    )
                    empty.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
                    present(empty, animated: true)
                    return
                }
                let sheet = UIAlertController(title: String(localized: "Mover para grupo"), message: nil, preferredStyle: .actionSheet)
                for group in eligible {
                    let title = (group.published == true) ? "✓ \(group.name)" : group.name
                    sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                        self?.togglePublish(group)
                    })
                }
                sheet.addAction(UIAlertAction(title: String(localized: "Cancelar"), style: .cancel))
                if let pop = sheet.popoverPresentationController {
                    pop.barButtonItem = navigationItem.rightBarButtonItem
                }
                present(sheet, animated: true)
            } catch {
                let err = UIAlertController(title: String(localized: "Erro"), message: error.localizedDescription, preferredStyle: .alert)
                err.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
                present(err, animated: true)
            }
        }
    }

    private func togglePublish(_ group: NativeAPIClient.GroupDTO) {
        Task { @MainActor in
            do {
                if group.published == true {
                    try await NativeAPIClient.unpublishNote(noteId: noteId, fromGroupId: group.id)
                    statusLabel.text = String(localized: "Retirada de «\(group.name)»")
                } else {
                    try await NativeAPIClient.publishNote(noteId: noteId, toGroupId: group.id)
                    statusLabel.text = String(localized: "Movida para «\(group.name)»")
                }
            } catch {
                let err = UIAlertController(title: String(localized: "Erro"), message: error.localizedDescription, preferredStyle: .alert)
                err.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
                present(err, animated: true)
            }
        }
    }

    private func openSettings() {
        // Keep chrome metadata in sync with first-line title before editing settings.
        note = editor.currentDocument()
        let settings = NoteSettingsViewController(note: note, speakers: speakers) { [weak self] updated in
            guard let self else { return }
            self.note = updated
            self.updateTitle()
            LocalNoteCache.upsertNote(updated)
            self.scheduleSave()
            self.editor.pushNote(self.note, speakers: self.speakers)
        }
        let nav = UINavigationController(rootViewController: settings)
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(nav, animated: true)
    }

    private func openSpeakerPicker(forSection: Bool) {
        let picker = SpeakerPickerViewController(mode: .pick(selectedId: note.noteSpeakerId), onPicked: { [weak self] speakerId in
            guard let self else { return }
            guard let speakerId,
                  let speaker = self.speakers.first(where: { $0.id == speakerId })
                    ?? LocalNoteCache.loadSpeakers().first(where: { $0.id == speakerId })
            else {
                if !forSection {
                    self.note.noteSpeakerId = nil
                    self.refreshSpeakerChip()
                    LocalNoteCache.upsertNote(self.note)
                    self.scheduleSave()
                }
                return
            }
            if forSection {
                self.editor.insertSpeakerSection(speakerId: speaker.id, name: speaker.name)
            } else {
                self.note.noteSpeakerId = speakerId
                self.refreshSpeakerChip()
                LocalNoteCache.upsertNote(self.note)
                self.scheduleSave()
            }
        })
        let nav = UINavigationController(rootViewController: picker)
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(nav, animated: true)
    }

    private func shareNote() {
        let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "Reunião") : note.title
        let url = NativeAPIClient.baseURL.appendingPathComponent("n/\(note.id)")
        let vc = UIActivityViewController(activityItems: [title, note.preview, url], applicationActivities: nil)
        if let pop = vc.popoverPresentationController {
            pop.barButtonItem = navigationItem.rightBarButtonItem
        }
        present(vc, animated: true)
    }

    private func confirmDelete() {
        let alert = UIAlertController(title: nil, message: String(localized: "Excluir esta nota?"), preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: String(localized: "Cancelar"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "Excluir nota"), style: .destructive) { [weak self] _ in
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
