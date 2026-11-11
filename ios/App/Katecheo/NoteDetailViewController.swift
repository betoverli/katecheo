import UIKit

/// Native note chrome + native miolo (`NativeNoteEditorView`).
final class NoteDetailViewController: UIViewController, NativeNoteEditorViewDelegate {
    private enum SyncState {
        case idle
        case saving
        case synced
        case pendingLocal
    }

    private let noteId: String
    private var note: NativeAPIClient.NoteDocument
    private var speakers: [NativeAPIClient.SpeakerDTO] = []
    private let editor = NativeNoteEditorView()
    private var saveWork: DispatchWorkItem?
    private let speakerChip = UIButton(type: .system)
    private let speakerChipRemove = UIButton(type: .system)
    private let speakerChipRow = UIStackView()
    private let topChrome = UIStackView()
    private let syncButton = UIButton(type: .system)
    private var syncState: SyncState = .idle
    /// Local edits since the last clean `pushNote` — blocks API refresh from wiping the caret/IME.
    private var hasLocalEdits = false
    /// Granted (Shared) notes are readable; mutations stay with the owner.
    private var isGrantedReadOnly: Bool

    init(noteId: String, initial: NativeAPIClient.NoteDocument?, grantedReadOnly: Bool = false) {
        self.noteId = noteId
        self.note = initial ?? NativeAPIClient.emptyNote(id: noteId)
        self.isGrantedReadOnly = grantedReadOnly
        super.init(nibName: nil, bundle: nil)
        // Hide the root tab bar for the whole push/pop transition (no flicker).
        hidesBottomBarWhenPushed = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Apply Light-editor override BEFORE pushNote so speaker/pill bakes resolve Light.
        applyEditorAppearanceOverride()
        KCChrome.styleCanvas(view)
        // Title lives in the editor body (first line) — compact nav, no large-title gap.
        title = nil
        navigationItem.title = nil
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.backButtonDisplayMode = .minimal
        applyEditorChrome()

        syncButton.translatesAutoresizingMaskIntoConstraints = false
        syncButton.addTarget(self, action: #selector(syncIconTapped), for: .touchUpInside)
        syncButton.accessibilityLabel = String(localized: "Status da sincronização")
        NSLayoutConstraint.activate([
            syncButton.widthAnchor.constraint(equalToConstant: 28),
            syncButton.heightAnchor.constraint(equalToConstant: 28),
        ])
        applySyncState(.idle)

        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), style: .plain, target: self, action: #selector(openMore)),
            UIBarButtonItem(customView: syncButton),
        ]
        navigationItem.rightBarButtonItems?.first?.accessibilityLabel = String(localized: "Mais opções da nota")

        topChrome.axis = .vertical
        topChrome.spacing = KCDesign.Space.xxs
        topChrome.alignment = .leading
        topChrome.translatesAutoresizingMaskIntoConstraints = false
        topChrome.backgroundColor = KCDesign.canvas
        topChrome.isLayoutMarginsRelativeArrangement = true
        topChrome.layoutMargins = UIEdgeInsets(
            top: KCDesign.Space.xxs,
            left: KCDesign.Space.md,
            bottom: 0,
            right: KCDesign.Space.md
        )

        speakerChipRow.axis = .horizontal
        speakerChipRow.spacing = KCDesign.Space.xxs
        speakerChipRow.alignment = .center
        speakerChipRow.isHidden = true

        var chipConfig = UIButton.Configuration.filled()
        chipConfig.cornerStyle = .capsule
        chipConfig.baseBackgroundColor = KCDesign.surface.withAlphaComponent(0.7)
        chipConfig.baseForegroundColor = .secondaryLabel
        chipConfig.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
        chipConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var out = incoming
            out.font = KCDesign.preferred(.footnote, weight: .medium)
            return out
        }
        speakerChip.configuration = chipConfig
        speakerChip.addTarget(self, action: #selector(editWholeSpeaker), for: .touchUpInside)
        speakerChip.accessibilityLabel = String(localized: "Speaker da nota")

        speakerChipRemove.setTitle("×", for: .normal)
        speakerChipRemove.titleLabel?.font = KCDesign.preferred(.title3, weight: .regular)
        speakerChipRemove.setTitleColor(.secondaryLabel, for: .normal)
        speakerChipRemove.addTarget(self, action: #selector(clearWholeSpeaker), for: .touchUpInside)
        speakerChipRemove.accessibilityLabel = String(localized: "Remover speaker")
        speakerChipRemove.widthAnchor.constraint(equalToConstant: 36).isActive = true
        speakerChipRemove.heightAnchor.constraint(equalToConstant: 36).isActive = true

        speakerChipRow.addArrangedSubview(speakerChip)
        speakerChipRow.addArrangedSubview(speakerChipRemove)
        topChrome.addArrangedSubview(speakerChipRow)

        editor.delegate = self
        editor.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topChrome)
        view.addSubview(editor)

        NSLayoutConstraint.activate([
            topChrome.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topChrome.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topChrome.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            editor.topAnchor.constraint(equalTo: topChrome.bottomAnchor),
            editor.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            editor.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            editor.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // Start from the full on-device catalog — never an empty note-scoped list.
        speakers = isGrantedReadOnly ? [] : LocalNoteCache.loadSpeakers()
        editor.pushNote(note, speakers: speakers, readOnly: isGrantedReadOnly)
        refreshSpeakerChip()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(noteDidChangeExternally(_:)),
            name: .nativeNoteDidChange,
            object: nil
        )
        Task { await refreshFromAPI() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Keep the nav compact while editing (parent Caderno uses large titles).
        navigationController?.navigationBar.prefersLargeTitles = false
        applyEditorAppearanceOverride()
        applyEditorChrome()
        // Opening a note clears Shared unread for that id (build-238).
        KCActivityStore.markSharedNoteOpened(noteId)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent || isBeingDismissed {
            if !isGrantedReadOnly {
                // Flush editor document (incl. tags) before pop so a pending debounce
                // can't be cancelled empty-handed in deinit.
                note = editor.currentDocument()
                note.id = noteId
                LocalNoteCache.upsertNote(note)
                saveWork?.cancel()
                Task { await self.persist() }
            } else {
                saveWork?.cancel()
            }

            clearEditorAppearanceOverride()
            navigationController?.navigationBar.prefersLargeTitles = true
            // Restore tab chrome (screenBackground) when popping back to Caderno.
            if let nav = navigationController {
                KCChrome.applyNavigationBarAppearance(to: nav.navigationBar)
                nav.view.backgroundColor = KCDesign.screenBackground
            }
            AppAppearance.apply()
        }
    }

    /// Nav + page fill match the warm editor canvas (not the darker tab screenBackground).
    private func applyEditorChrome() {
        KCChrome.styleCanvas(view)
        topChrome.backgroundColor = KCDesign.canvas
        editor.backgroundColor = KCDesign.canvas
        if let nav = navigationController {
            KCChrome.applyNavigationBarAppearance(to: nav.navigationBar, background: KCDesign.canvas)
            nav.view.backgroundColor = KCDesign.canvas
        }
    }

    /// Optional: keep note editing Light while the rest of the app stays Dark/System.
    private func applyEditorAppearanceOverride() {
        guard AppAppearance.keepEditorInLightMode else {
            clearEditorAppearanceOverride()
            return
        }
        overrideUserInterfaceStyle = .light
        navigationController?.overrideUserInterfaceStyle = .light
        editor.overrideUserInterfaceStyle = .light
    }

    private func clearEditorAppearanceOverride() {
        overrideUserInterfaceStyle = .unspecified
        navigationController?.overrideUserInterfaceStyle = .unspecified
        editor.overrideUserInterfaceStyle = .unspecified
    }

    @objc private func noteDidChangeExternally(_ note: Notification) {
        guard let id = note.object as? String, id == noteId else { return }
        Task { await refreshFromAPI() }
    }

    deinit {
        saveWork?.cancel()
    }

    private func updateTitle() {
        title = nil
        navigationItem.title = nil
    }

    private func applySyncState(_ state: SyncState) {
        syncState = state
        let symbol: String
        let color: UIColor
        let label: String
        switch state {
        case .idle, .synced:
            symbol = "checkmark.icloud"
            color = KCDesign.accent.withAlphaComponent(state == .idle ? 0.35 : 0.85)
            label = String(localized: "Nota sincronizada")
        case .saving:
            symbol = "arrow.triangle.2.circlepath.icloud"
            color = .secondaryLabel
            label = String(localized: "Salvando…")
        case .pendingLocal:
            symbol = "icloud.and.arrow.up"
            color = KCDesign.accent
            label = String(localized: "Salvo neste aparelho")
        }
        let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        syncButton.setImage(UIImage(systemName: symbol, withConfiguration: config), for: .normal)
        syncButton.tintColor = color
        syncButton.accessibilityLabel = label
        syncButton.accessibilityValue = label
    }

    @objc private func syncIconTapped() {
        // Subtle affordance only — no banner text. VoiceOver reads the accessibility label.
        KCHaptics.selection()
        UIAccessibility.post(notification: .announcement, argument: syncButton.accessibilityLabel)
    }

    private func refreshFromAPI() async {
        do {
            async let notePack = NativeAPIClient.getNote(id: noteId)
            async let catalog = NativeAPIClient.listSpeakers()
            let packed = try await notePack
            let fullCatalog = (try? await catalog) ?? LocalNoteCache.loadSpeakers()
            await MainActor.run {
                if packed.via == "grant" {
                    self.isGrantedReadOnly = true
                }
                // Always keep the full registered catalog for the picker (TF200 #3).
                // `getNote.speakers` is note-scoped; merge already ran inside getNote.
                if self.isGrantedReadOnly {
                    self.speakers = packed.speakers
                } else {
                    self.speakers = fullCatalog.isEmpty
                        ? LocalNoteCache.mergeSpeakers(packed.speakers)
                        : fullCatalog
                }
                if self.hasLocalEdits, !self.isGrantedReadOnly {
                    // Keep the live editor buffer — only refresh speaker chrome / metadata.
                    self.editor.updateSpeakers(self.speakers)
                    self.refreshSpeakerChip()
                    return
                }
                self.note = packed.note
                self.updateTitle()
                self.applySyncState(.synced)
                self.editor.pushNote(self.note, speakers: self.speakers, readOnly: self.isGrantedReadOnly)
                self.hasLocalEdits = false
                self.refreshSpeakerChip()
            }
        } catch {
            await MainActor.run {
                self.speakers = self.isGrantedReadOnly ? self.speakers : LocalNoteCache.loadSpeakers()
                self.applySyncState(.pendingLocal)
                if !self.hasLocalEdits {
                    self.editor.pushNote(self.note, speakers: self.speakers, readOnly: self.isGrantedReadOnly)
                } else {
                    self.editor.updateSpeakers(self.speakers)
                }
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
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 7, weight: .bold)
        config.imagePadding = 6
        if let color = UIColor(kcHex: speaker.color) {
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
        guard !isGrantedReadOnly else { return }
        var next = document
        next.id = noteId
        // Keep VC-owned metadata. Tags now live under the title in the editor
        // (NoteEditorTagsStrip) — never overwrite them with the stale VC copy
        // (build-238: tags vanished on exit/reopen).
        next.happenedAt = note.happenedAt
        next.noteSpeakerId = note.noteSpeakerId
        next.visibility = note.visibility
        next.schemaVersion = 1
        note = next
        hasLocalEdits = true
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
                    presentBriefAlert(String(localized: "Link da Bíblia indisponível"))
                    return
                }
                await UIApplication.shared.open(url)
            } catch {
                presentBriefAlert(String(localized: "Não abriu a Bíblia: \(error.localizedDescription)"))
            }
        }
    }

    func nativeNoteEditorRequestInsertBibleRef(_ editor: NativeNoteEditorView) {
        let picker = BibleRefInsertPicker { [weak self] ref in
            self?.editor.insertBibleRef(ref)
        }
        KCSheetPresenter.present(picker, from: self)
    }

    func nativeNoteEditorRequestSpeaker(_ editor: NativeNoteEditorView) {
        openSpeakerPicker(forSection: true)
    }

    func nativeNoteEditorRequestRenameSpeaker(
        _ editor: NativeNoteEditorView,
        sectionId: String,
        currentSpeakerId: String?
    ) {
        let seed = LocalNoteCache.mergeSpeakers(speakers)
        speakers = seed
        editor.updateSpeakers(seed)
        let picker = SpeakerPickerViewController(
            mode: .pick(selectedId: currentSpeakerId),
            seed: seed,
            onPicked: { [weak self] speakerId in
                guard let self else { return }
                guard let speakerId,
                      let speaker = self.speakers.first(where: { $0.id == speakerId })
                        ?? LocalNoteCache.loadSpeakers().first(where: { $0.id == speakerId })
                else { return }
                self.editor.renameSpeakerSection(sectionId: sectionId, speakerId: speaker.id, name: speaker.name)
            },
            onManaged: { [weak self] in
                guard let self else { return }
                self.speakers = LocalNoteCache.loadSpeakers()
                self.editor.updateSpeakers(self.speakers)
            }
        )
        KCSheetPresenter.present(picker, from: self)
    }

    private func presentBriefAlert(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
        present(alert, animated: true)
    }

    private func scheduleSave() {
        guard !isGrantedReadOnly else { return }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { await self.persist() }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
        applySyncState(.saving)
    }

    private func persist() async {
        guard !isGrantedReadOnly else { return }
        do {
            let saved = try await NativeAPIClient.upsertNote(note)
            await MainActor.run {
                // Don't pushNote after save — that would reset caret / undo / IME.
                self.note.updatedAt = saved.updatedAt
                self.hasLocalEdits = false
                self.applySyncState(.synced)
            }
        } catch NativeAPIClient.APIError.unauthorized {
            NativeOutbox.enqueueNoteUpsert(note)
            await MainActor.run {
                self.applySyncState(.pendingLocal)
            }
        } catch {
            NativeOutbox.enqueueNoteUpsert(note)
            await MainActor.run {
                self.applySyncState(.pendingLocal)
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
        KCConfirmation.presentActionSheet(
            sheet,
            from: self,
            barButtonItem: navigationItem.rightBarButtonItems?.first
        )
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
                KCConfirmation.presentActionSheet(
                    sheet,
                    from: self,
                    barButtonItem: navigationItem.rightBarButtonItems?.first
                )
            } catch {
                presentBriefAlert(error.localizedDescription)
            }
        }
    }

    private func togglePublish(_ group: NativeAPIClient.GroupDTO) {
        Task { @MainActor in
            do {
                if group.published == true {
                    try await NativeAPIClient.unpublishNote(noteId: noteId, fromGroupId: group.id)
                } else {
                    try await NativeAPIClient.publishNote(noteId: noteId, toGroupId: group.id)
                }
                applySyncState(.synced)
            } catch {
                presentBriefAlert(error.localizedDescription)
            }
        }
    }

    private func openSettings() {
        note = editor.currentDocument()
        let settings = NoteSettingsViewController(note: note, speakers: speakers) { [weak self] updated in
            guard let self else { return }
            self.note = updated
            self.updateTitle()
            LocalNoteCache.upsertNote(updated)
            self.scheduleSave()
            self.editor.pushNote(self.note, speakers: self.speakers)
            self.hasLocalEdits = false
        }
        KCSheetPresenter.present(settings, from: self)
    }

    private func openSpeakerPicker(forSection: Bool) {
        // Seed with the full catalog (cache ∪ in-memory), never the note-scoped subset.
        let seed = LocalNoteCache.mergeSpeakers(speakers)
        speakers = seed
        editor.updateSpeakers(seed)
        let picker = SpeakerPickerViewController(
            mode: .pick(selectedId: forSection ? nil : note.noteSpeakerId),
            seed: seed,
            onPicked: { [weak self] speakerId in
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
            },
            onManaged: { [weak self] in
                guard let self else { return }
                self.speakers = LocalNoteCache.loadSpeakers()
                self.editor.updateSpeakers(self.speakers)
            }
        )
        KCSheetPresenter.present(picker, from: self)
    }

    private func shareNote() {
        let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "Reunião") : note.title
        let url = NativeAPIClient.baseURL.appendingPathComponent("n/\(note.id)")
        let vc = UIActivityViewController(activityItems: [title, note.preview, url], applicationActivities: nil)
        KCConfirmation.presentActivity(
            vc,
            from: self,
            barButtonItem: navigationItem.rightBarButtonItems?.first
        )
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
        KCConfirmation.presentActionSheet(
            alert,
            from: self,
            barButtonItem: navigationItem.rightBarButtonItems?.first
        )
    }
}
