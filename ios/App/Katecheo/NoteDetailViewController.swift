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
    private let syncButton = UIButton(type: .system)
    private var syncState: SyncState = .idle
    /// Local edits since the last clean `pushNote` — blocks API refresh from wiping the caret/IME.
    private var hasLocalEdits = false
    /// After the editor paints this note, the on-screen buffer is source of truth while this VC is open.
    /// Refresh / outbox / self-save may update speakers + sync chrome, but must never `pushNote`.
    private var screenBufferIsSourceOfTruth = false
    /// Posted with `.nativeNoteDidChange` so this VC can ignore notifications it emitted itself.
    static let noteChangeSenderKey = "katecheo.noteChangeSender"
    /// Granted (Shared) notes are readable; mutations stay with the owner.
    private var isGrantedReadOnly: Bool
    /// Author of a granted / group note — used for report & block.
    private var sharedAuthorUserId: String?
    private var sharedAuthorName: String?
    /// When set (compose from a notebook group), every sync keeps the note published to that group.
    private let publishGroupId: String?
    private var editorTopConstraint: NSLayoutConstraint?
    private var editorBottomConstraint: NSLayoutConstraint?
    private var editorLeadingConstraint: NSLayoutConstraint?
    private var editorTrailingConstraint: NSLayoutConstraint?
    /// Avoid re-laying out glyphs on every Auto Layout pass once the column has size.
    private var didEnsureGlyphsForCurrentBounds = false

    init(
        noteId: String,
        initial: NativeAPIClient.NoteDocument?,
        grantedReadOnly: Bool = false,
        sharedAuthorUserId: String? = nil,
        sharedAuthorName: String? = nil,
        publishGroupId: String? = nil
    ) {
        self.noteId = noteId
        self.note = initial ?? NativeAPIClient.emptyNote(id: noteId)
        self.isGrantedReadOnly = grantedReadOnly
        self.sharedAuthorUserId = sharedAuthorUserId
        self.sharedAuthorName = sharedAuthorName
        self.publishGroupId = publishGroupId
        super.init(nibName: nil, bundle: nil)
        // Compact push hides the tab bar; regular-width split secondary keeps it visible.
        // NotebookSplitViewController updates this via `applyTabBarHidingForSplit`.
        hidesBottomBarWhenPushed = true
    }

    /// Note id for split routing / selection highlight.
    var openedNoteId: String { noteId }

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

        // Whole-note speaker lives in the editor tags strip (scrolls with content) — no pinned top chrome.
        editor.delegate = self
        editor.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(editor)

        editorTopConstraint = editor.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
        editorBottomConstraint = editor.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        editorLeadingConstraint = editor.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        editorTrailingConstraint = editor.trailingAnchor.constraint(equalTo: view.trailingAnchor)

        NSLayoutConstraint.activate([
            editorTopConstraint!,
            editorBottomConstraint!,
            editorLeadingConstraint!,
            editorTrailingConstraint!,
        ])
        // Fill the secondary column; Notes-like horizontal insets live in the editor text container.
        updateEditorReadingInsets()

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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(outboxDidFlush),
            name: .nativeOutboxDidFlush,
            object: nil
        )
        // Returning from an external Bible app: iOS may have snapshotted light+dark and left
        // once-resolved title / speaker-header colors stale. Re-assert override + re-bake.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshAppearanceAfterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshAppearanceAfterForeground),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        if !isGrantedReadOnly, LocalNoteCache.note(id: noteId) != nil {
            // Prefer dirty/newer disk over the in-memory seed (candidate = live VC note).
            let preferred = LocalNoteCache.preferredNote(over: note)
            if preferred != note {
                note = preferred
                editor.pushNote(note, speakers: speakers, readOnly: false)
            }
            if LocalNoteCache.isDirtyOrPending(noteId) {
                hasLocalEdits = true
                applySyncState(.pendingLocal)
            }
        }
        // Initial paint done — keep the live buffer across persist / outbox / SWR refresh.
        screenBufferIsSourceOfTruth = true
        Task { await refreshFromAPI() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Split secondary often loads at width 0; once the column has size, force glyphs.
        let width = view.bounds.width
        if width > 1, !didEnsureGlyphsForCurrentBounds {
            didEnsureGlyphsForCurrentBounds = true
            editor.ensureVisibleGlyphsLaidOut()
        } else if width <= 1 {
            didEnsureGlyphsForCurrentBounds = false
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Keep the nav compact while editing (parent Caderno uses large titles).
        navigationController?.navigationBar.prefersLargeTitles = false
        // Never show the split's displayMode control on the detail — empty Liquid Glass circle.
        navigationItem.leftBarButtonItem = nil
        navigationItem.leftBarButtonItems = []
        navigationItem.hidesBackButton = true
        if let split = splitViewController {
            if #available(iOS 14.5, *) {
                split.displayModeButtonVisibility = .never
            }
        }
        // Regular split secondary: keep tab bar. Compact push: hide it.
        if let split = splitViewController as? NotebookSplitViewController {
            applyTabBarHidingForSplit(isCollapsed: split.isCollapsed)
        } else if let split = splitViewController as? GroupsSplitViewController {
            applyTabBarHidingForSplit(isCollapsed: split.isCollapsed)
        } else if traitCollection.horizontalSizeClass == .compact {
            hidesBottomBarWhenPushed = true
        }
        updateEditorReadingInsets()
        applyEditorAppearanceOverride()
        applyEditorChrome()
        editor.refreshAppearanceForCurrentTraits(forceAttachments: true)
        // Opening a note clears Shared unread for that id (build-238).
        KCActivityStore.markSharedNoteOpened(noteId)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // UIKit can re-inject displayModeButtonItem after appear — clear again.
        navigationItem.leftBarButtonItem = nil
        navigationItem.leftBarButtonItems = []
        ensureEditorContentVisible()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.horizontalSizeClass != traitCollection.horizontalSizeClass {
            updateEditorReadingInsets()
            if let split = splitViewController as? NotebookSplitViewController {
                applyTabBarHidingForSplit(isCollapsed: split.isCollapsed)
            } else if let split = splitViewController as? GroupsSplitViewController {
                applyTabBarHidingForSplit(isCollapsed: split.isCollapsed)
            }
        }
    }

    /// Editor fills the column; on regular iPad use ~24pt Notes-like text insets (no narrow max-width column).
    private func updateEditorReadingInsets() {
        let padRegular = PadChrome.isPad && traitCollection.horizontalSizeClass == .regular
        editor.applyPadReadingInsets(padRegular)
    }

    /// Pop on compact; empty secondary column on regular split (Caderno or Grupos).
    private func dismissAfterLeavingNote() {
        if let split = splitViewController as? NotebookSplitViewController {
            split.clearDetailAfterDeletingNote(id: noteId)
        } else if let split = splitViewController as? GroupsSplitViewController {
            split.clearDetailAfterDeletingNote(id: noteId)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }

    @objc private func refreshAppearanceAfterForeground() {
        guard viewIfLoaded?.window != nil else { return }
        applyEditorAppearanceOverride()
        applyEditorChrome()
        editor.refreshAppearanceForCurrentTraits(forceAttachments: true)
        refreshSpeakerChip()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent || isBeingDismissed {
            if !isGrantedReadOnly {
                // Flush editor document (incl. tags + noteSpeakerId on documentBase)
                // before pop so a pending debounce can't be cancelled empty-handed in deinit.
                // Keep VC-owned happenedAt / visibility the attributed round-trip does not encode.
                let happenedAt = note.happenedAt
                let visibility = note.visibility
                var draft = editor.currentDocument()
                draft.id = noteId
                draft.happenedAt = happenedAt
                draft.visibility = visibility
                note = draft
                // Only rewrite disk when content actually changed vs the on-disk copy.
                // Reopen → close without typing must not restamp updatedAt / replace the outbox job.
                let diskChanged = Self.contentDiffers(LocalNoteCache.note(id: noteId), draft)
                saveWork?.cancel()
                if diskChanged {
                    note = LocalNoteCache.recordLocalEdit(draft)
                    Task { await self.persist() }
                } else if hasLocalEdits || LocalNoteCache.isDirtyOrPending(noteId) {
                    // Content already on disk (typing path); still flush a cancelled debounce.
                    Task { await self.persist() }
                }
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

    /// Server fills at least one gap the incomplete seed is missing (title and/or body).
    private static func serverFillsIncompleteSeed(
        seed: NativeAPIClient.NoteDocument,
        server: NativeAPIClient.NoteDocument
    ) -> Bool {
        let seedTitleEmpty = seed.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let seedBodyEmpty = seed.listBodyPreview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let serverTitle = !server.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let serverBody = !server.listBodyPreview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if seedTitleEmpty, serverTitle { return true }
        if seedBodyEmpty, serverBody { return true }
        return false
    }

    /// Compare note payload ignoring fields the editor round-trip may normalize
    /// (`updatedAt`, empty span arrays ↔ nil, schemaVersion). Prevents reopen→close
    /// without typing from restamping / replacing the outbox job.
    private static func contentDiffers(
        _ a: NativeAPIClient.NoteDocument?,
        _ b: NativeAPIClient.NoteDocument
    ) -> Bool {
        guard let left = a else { return true }
        return normalizeForCompare(left) != normalizeForCompare(b)
    }

    private static func normalizeForCompare(_ note: NativeAPIClient.NoteDocument) -> NativeAPIClient.NoteDocument {
        var next = note
        next.updatedAt = ""
        next.schemaVersion = 1
        next.title = next.title.trimmingCharacters(in: .whitespacesAndNewlines)
        next.tags = next.tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        next.body.blocks = next.body.blocks.map { normalizeBlock($0) }
        return next
    }

    private static func normalizeBlock(_ block: NativeAPIClient.LineBlock) -> NativeAPIClient.LineBlock {
        var b = block
        // Block ids may be regenerated by the attributed round-trip; compare structure/text only.
        b.id = ""
        if let spans = b.spans {
            b.spans = spans.isEmpty ? nil : spans
        }
        if let children = b.blocks {
            b.blocks = children.isEmpty ? nil : children.map { normalizeBlock($0) }
        }
        return b
    }

    /// Nav + page fill match the warm editor canvas (not the darker tab screenBackground).
    private func applyEditorChrome() {
        KCChrome.styleCanvas(view)
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

    /// After the split column is on screen, re-paint the document at real bounds so
    /// title/body glyphs exist (TextKit often skips fragments when first painted at width 0).
    func ensureEditorContentVisible() {
        loadViewIfNeeded()
        didEnsureGlyphsForCurrentBounds = false
        view.layoutIfNeeded()
        editor.pushNote(note, speakers: speakers, readOnly: isGrantedReadOnly)
        editor.ensureVisibleGlyphsLaidOut()
        didEnsureGlyphsForCurrentBounds = view.bounds.width > 1
    }

    @objc private func noteDidChangeExternally(_ note: Notification) {
        guard let id = note.object as? String, id == noteId else { return }
        // Ignore the notification this VC posted after its own persist — list still receives it.
        if let sender = note.userInfo?[Self.noteChangeSenderKey] as? ObjectIdentifier,
           sender == ObjectIdentifier(self)
        {
            return
        }
        Task { await refreshFromAPI() }
    }

    @objc private func outboxDidFlush() {
        Task { await refreshFromAPI(force: true) }
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

    private func refreshFromAPI(force: Bool = false) async {
        do {
            async let notePack = NativeAPIClient.getNote(id: noteId, force: force)
            async let catalog = NativeAPIClient.listSpeakers()
            let packed = try await notePack
            let fullCatalog = (try? await catalog) ?? LocalNoteCache.loadSpeakers()
            let offline = NativeSWR.consumeOfflineFallback(.note(noteId))
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
                let localDirty = !self.isGrantedReadOnly && (
                    self.hasLocalEdits || LocalNoteCache.isDirtyOrPending(self.noteId)
                )
                // Incomplete seed (missing title and/or body) must still accept a fuller getNote
                // paint — otherwise iPad/group opens stay blank under the buffer lock.
                let seedIncomplete = self.note.kcIsIncompleteEditorSeed
                let serverFillsGap = Self.serverFillsIncompleteSeed(seed: self.note, server: packed.note)
                if seedIncomplete, serverFillsGap, !localDirty {
                    self.note = packed.note
                    self.updateTitle()
                    self.applySyncState(offline ? .pendingLocal : .synced)
                    self.editor.pushNote(self.note, speakers: self.speakers, readOnly: self.isGrantedReadOnly)
                    self.hasLocalEdits = false
                    self.refreshSpeakerChip()
                    return
                }
                // While this detail screen owns the buffer, never rewrite the editor — even after
                // a clean persist (hasLocalEdits=false) or outbox flush. List still refreshes via
                // `.nativeNoteDidChange`; caret / IME stay put.
                if localDirty || self.screenBufferIsSourceOfTruth {
                    // Keep the live editor buffer — only refresh speaker chrome / metadata.
                    if let disk = LocalNoteCache.note(id: self.noteId) {
                        self.note.updatedAt = LocalNoteCache.maxUpdatedAt(self.note.updatedAt, disk.updatedAt)
                    }
                    self.editor.updateSpeakers(self.speakers)
                    self.refreshSpeakerChip()
                    let pending = offline || LocalNoteCache.isDirtyOrPending(self.noteId)
                    if localDirty {
                        self.applySyncState(pending ? .pendingLocal : .saving)
                    } else {
                        self.applySyncState(pending ? .pendingLocal : .synced)
                    }
                    return
                }
                // Apply server only when local isn't dirty and server isn't older than local.
                if !self.isGrantedReadOnly,
                   LocalNoteCache.isUpdatedAt(self.note.updatedAt, newerThan: packed.note.updatedAt)
                {
                    self.editor.updateSpeakers(self.speakers)
                    self.refreshSpeakerChip()
                    self.applySyncState(offline ? .pendingLocal : .synced)
                    return
                }
                self.note = packed.note
                self.updateTitle()
                self.applySyncState(offline ? .pendingLocal : .synced)
                self.editor.pushNote(self.note, speakers: self.speakers, readOnly: self.isGrantedReadOnly)
                self.hasLocalEdits = false
                self.refreshSpeakerChip()
            }
        } catch {
            await MainActor.run {
                if let disk = LocalNoteCache.note(id: self.noteId), !self.isGrantedReadOnly {
                    // Prefer disk for VC metadata, but do not clobber the live buffer while open.
                    if !self.screenBufferIsSourceOfTruth {
                        self.note = LocalNoteCache.preferredNote(over: disk)
                    } else {
                        self.note.updatedAt = LocalNoteCache.maxUpdatedAt(
                            self.note.updatedAt,
                            LocalNoteCache.preferredNote(over: disk).updatedAt
                        )
                    }
                }
                self.speakers = self.isGrantedReadOnly ? self.speakers : LocalNoteCache.loadSpeakers()
                self.applySyncState(.pendingLocal)
                if self.screenBufferIsSourceOfTruth || self.hasLocalEdits {
                    self.editor.updateSpeakers(self.speakers)
                } else {
                    self.editor.pushNote(self.note, speakers: self.speakers, readOnly: self.isGrantedReadOnly)
                }
                self.refreshSpeakerChip()
            }
        }
    }

    /// Keep the tags-strip speaker chip in sync with `note.noteSpeakerId` + catalog.
    private func refreshSpeakerChip() {
        // Prefer the editor document (source of truth while open); fall back to VC note.
        let id = editor.isReady ? editor.currentDocument().noteSpeakerId : note.noteSpeakerId
        note.noteSpeakerId = id
        editor.refreshSpeakerChip()
    }

    // MARK: - NativeNoteEditorViewDelegate

    func nativeNoteEditorDidChange(_ editor: NativeNoteEditorView, document: NativeAPIClient.NoteDocument) {
        guard !isGrantedReadOnly else { return }
        var next = document
        next.id = noteId
        // Keep VC-owned metadata. Tags + whole-note speaker live on the editor
        // documentBase — never overwrite them with a stale VC copy (build-238 tags;
        // noteSpeakerId vanished on exit/reopen when only the VC chip was updated).
        next.happenedAt = note.happenedAt
        next.visibility = note.visibility
        next.schemaVersion = 1
        // Stamp updatedAt at edit time and keep SWR memory aligned with disk.
        note = LocalNoteCache.recordLocalEdit(next)
        hasLocalEdits = true
        updateTitle()
        scheduleSave()
    }

    func nativeNoteEditor(_ editor: NativeNoteEditorView, openBibleRef ref: NoteDocumentCodec.BibleRefPayload) {
        openBibleRef(ref)
    }

    /// Opens the user's Bible app from a note pill — local URL first, network only as fallback.
    func openBibleRef(_ ref: NoteDocumentCodec.BibleRefPayload) {
        let prefs = BibleDeepLink.loadLocalPrefs()
        let passage = BibleDeepLink.Passage(
            bookId: ref.bookId,
            chapter: ref.chapter,
            verseStart: ref.verseStart,
            verseEnd: ref.verseEnd
        )
        if let url = BibleDeepLink.urlForOpening(
            appId: prefs.appId,
            passage: passage,
            translationId: prefs.translationId,
            preferNative: prefs.preferNative,
            locale: prefs.locale
        ) {
            BibleDeepLink.open(url)
            return
        }

        // Rare: unknown book / corrupt prefs — resolve via API with a short timeout + spinner.
        let apiPassage = NativeAPIClient.PassageDTO(
            bookId: ref.bookId,
            chapter: ref.chapter,
            verseStart: ref.verseStart,
            verseEnd: ref.verseEnd
        )
        showBibleLinkSpinner(true)
        Task { @MainActor in
            defer { showBibleLinkSpinner(false) }
            do {
                let link = try await NativeAPIClient.resolveBibleLink(
                    passage: apiPassage,
                    appId: prefs.appId,
                    translationId: prefs.translationId,
                    preferNative: prefs.preferNative,
                    timeout: 8
                )
                guard let url = URL(string: link.url) else {
                    presentBriefAlert(String(localized: "Link da Bíblia indisponível"))
                    return
                }
                BibleDeepLink.open(url)
            } catch {
                #if DEBUG
                print("[NoteDetail] openBibleRef failed: \(error)")
                #endif
                presentBriefAlert(String(localized: "Não foi possível gerar o link agora. Tente de novo."))
            }
        }
    }

    private var bibleLinkSpinnerItem: UIBarButtonItem?

    private func showBibleLinkSpinner(_ visible: Bool) {
        if visible {
            guard bibleLinkSpinnerItem == nil else { return }
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.startAnimating()
            spinner.accessibilityIdentifier = "bible-link-spinner"
            let item = UIBarButtonItem(customView: spinner)
            bibleLinkSpinnerItem = item
            var items = navigationItem.rightBarButtonItems ?? []
            items.insert(item, at: 0)
            navigationItem.rightBarButtonItems = items
        } else if let item = bibleLinkSpinnerItem {
            bibleLinkSpinnerItem = nil
            navigationItem.rightBarButtonItems = (navigationItem.rightBarButtonItems ?? []).filter { $0 !== item }
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

    func nativeNoteEditorRequestNoteSpeaker(_ editor: NativeNoteEditorView) {
        // Chip → picker: select against the live document speaker id.
        note.noteSpeakerId = editor.currentDocument().noteSpeakerId
        openSpeakerPicker(forSection: false)
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
        // Carry the edit-time updatedAt through the outbox / wire payload.
        let payload = LocalNoteCache.note(id: noteId) ?? note
        do {
            let saved = try await NativeAPIClient.upsertNote(payload, publishToGroupId: publishGroupId)
            await MainActor.run {
                // Don't pushNote after save — that would reset caret / undo / IME.
                if !LocalNoteCache.isDirtyOrPending(self.noteId) {
                    self.note.updatedAt = saved.updatedAt
                    self.hasLocalEdits = false
                    self.applySyncState(.synced)
                } else {
                    self.applySyncState(.pendingLocal)
                }
                // Keep posting so Caderno / other screens refresh; tag sender so we ignore it here.
                NotificationCenter.default.post(
                    name: .nativeNoteDidChange,
                    object: self.noteId,
                    userInfo: [Self.noteChangeSenderKey: ObjectIdentifier(self)]
                )
            }
        } catch NativeAPIClient.APIError.http(let code, _) where code == 409 {
            LocalNoteCache.markSyncLimitReached(id: noteId)
            await MainActor.run {
                self.applySyncState(.pendingLocal)
            }
        } catch NativeAPIClient.APIError.unauthorized {
            LocalNoteCache.markPendingSync(id: noteId)
            NativeOutbox.enqueueNoteUpsert(payload, publishToGroupId: publishGroupId)
            await MainActor.run {
                self.applySyncState(.pendingLocal)
            }
        } catch {
            LocalNoteCache.markPendingSync(id: noteId)
            NativeOutbox.enqueueNoteUpsert(payload, publishToGroupId: publishGroupId)
            await MainActor.run {
                self.applySyncState(.pendingLocal)
            }
        }
    }

    @objc private func openMore() {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        if isGrantedReadOnly {
            sheet.addAction(UIAlertAction(title: String(localized: "Denunciar"), style: .default) { [weak self] _ in
                guard let self else { return }
                ReportBlockSupport.presentReport(
                    target: .note(
                        noteId: self.noteId,
                        authorUserId: self.sharedAuthorUserId,
                        authorName: self.sharedAuthorName ?? String(localized: "Nota compartilhada")
                    ),
                    from: self,
                    barButtonItem: self.navigationItem.rightBarButtonItems?.first
                )
            })
            if let authorId = sharedAuthorUserId, !authorId.isEmpty {
                sheet.addAction(UIAlertAction(title: String(localized: "Bloquear"), style: .destructive) { [weak self] _ in
                    guard let self else { return }
                    ReportBlockSupport.confirmBlock(
                        userId: authorId,
                        displayName: self.sharedAuthorName ?? String(localized: "esta pessoa"),
                        from: self,
                        barButtonItem: self.navigationItem.rightBarButtonItems?.first
                    ) {
                        self.dismissAfterLeavingNote()
                    }
                })
            }
            sheet.addAction(UIAlertAction(title: String(localized: "Compartilhar"), style: .default) { [weak self] _ in
                self?.shareNote()
            })
            sheet.addAction(UIAlertAction(title: String(localized: "Cancelar"), style: .cancel))
            KCConfirmation.presentActionSheet(
                sheet,
                from: self,
                barButtonItem: navigationItem.rightBarButtonItems?.first
            )
            return
        }
        sheet.addAction(UIAlertAction(title: String(localized: "Configurações"), style: .default) { [weak self] _ in
            self?.openSettings()
        })
        // Whole-note speaker is edited via the tags-strip chip (and Note Settings) — not the … menu.
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
        if LocalNoteCache.isAwaitingFirstSync(noteId) {
            presentBriefAlert(String(localized: "Disponível após sincronizar."))
            return
        }
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
            self.note = LocalNoteCache.recordLocalEdit(updated)
            self.hasLocalEdits = true
            self.updateTitle()
            self.scheduleSave()
            self.editor.pushNote(self.note, speakers: self.speakers)
            self.refreshSpeakerChip()
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
                        self.editor.setNoteSpeakerId(nil)
                        self.refreshSpeakerChip()
                    }
                    return
                }
                if forSection {
                    self.editor.insertSpeakerSection(speakerId: speaker.id, name: speaker.name)
                } else {
                    self.editor.setNoteSpeakerId(speakerId)
                    self.refreshSpeakerChip()
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
        if LocalNoteCache.isAwaitingFirstSync(noteId) {
            presentBriefAlert(String(localized: "Disponível após sincronizar."))
            return
        }
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
                    if LocalNoteCache.isAwaitingFirstSync(self.noteId) {
                        NativeAPIClient.discardLocalOnlyNote(id: self.noteId)
                    } else {
                        try await NativeAPIClient.deleteNote(id: self.noteId)
                    }
                    self.dismissAfterLeavingNote()
                } catch NativeAPIClient.APIError.unauthorized {
                    if LocalNoteCache.isAwaitingFirstSync(self.noteId) {
                        NativeAPIClient.discardLocalOnlyNote(id: self.noteId)
                    } else {
                        LocalNoteCache.removeNote(id: self.noteId)
                        NativeOutbox.enqueueNoteDelete(id: self.noteId)
                    }
                    self.dismissAfterLeavingNote()
                } catch {
                    if LocalNoteCache.isAwaitingFirstSync(self.noteId) {
                        NativeAPIClient.discardLocalOnlyNote(id: self.noteId)
                    } else {
                        LocalNoteCache.removeNote(id: self.noteId)
                        NativeOutbox.enqueueNoteDelete(id: self.noteId)
                    }
                    self.dismissAfterLeavingNote()
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

// MARK: - AppTests seams

extension NoteDetailViewController {
    var testing_editor: NativeNoteEditorView { editor }

    var testing_hasLocalEdits: Bool { hasLocalEdits }

    var testing_screenBufferIsSourceOfTruth: Bool { screenBufferIsSourceOfTruth }

    func testing_setHasLocalEdits(_ value: Bool) {
        hasLocalEdits = value
    }

    func testing_cancelPendingSave() {
        saveWork?.cancel()
        saveWork = nil
    }

    /// Mimic a successful online persist: dirty cleared, then post `.nativeNoteDidChange`
    /// the same way `persist()` does (with this VC as sender).
    func testing_simulateSuccessfulPersist() {
        let payload = LocalNoteCache.note(id: noteId) ?? note
        let revision = LocalNoteCache.syncMeta(for: noteId)?.localRevision
        LocalNoteCache.clearDirtyIfNotNewer(
            id: noteId,
            syncedUpdatedAt: payload.updatedAt,
            syncedRevision: revision
        )
        note.updatedAt = payload.updatedAt
        hasLocalEdits = false
        applySyncState(.synced)
        NotificationCenter.default.post(
            name: .nativeNoteDidChange,
            object: noteId,
            userInfo: [Self.noteChangeSenderKey: ObjectIdentifier(self)]
        )
    }

    /// External note-change notification (no sender) — as if another screen updated this id.
    func testing_postExternalNoteDidChange() {
        NotificationCenter.default.post(name: .nativeNoteDidChange, object: noteId)
    }

    func testing_refreshFromAPI(force: Bool = false) async {
        await refreshFromAPI(force: force)
    }

    func testing_outboxDidFlush() {
        outboxDidFlush()
    }
}
