import UIKit

@MainActor
protocol NativeNoteEditorViewDelegate: AnyObject {
    func nativeNoteEditorDidChange(_ editor: NativeNoteEditorView, document: NativeAPIClient.NoteDocument)
    func nativeNoteEditor(_ editor: NativeNoteEditorView, openBibleRef ref: NoteDocumentCodec.BibleRefPayload)
    func nativeNoteEditorRequestInsertBibleRef(_ editor: NativeNoteEditorView)
    func nativeNoteEditorRequestSpeaker(_ editor: NativeNoteEditorView)
    /// Change which catalog speaker owns an existing section (web: head is not typed).
    func nativeNoteEditorRequestRenameSpeaker(_ editor: NativeNoteEditorView, sectionId: String, currentSpeakerId: String?)
}

/// Fully native note body editor (Phase 7). UITextView only.
@MainActor
final class NativeNoteEditorView: UIView, UITextViewDelegate {
    weak var delegate: NativeNoteEditorViewDelegate?

    private let textView: NoteEditorTextView
    private let railLayoutManager: NoteSpeakerRailLayoutManager
    private let accessory = NoteEditorAccessoryBar()
    private var documentBase: NativeAPIClient.NoteDocument = NativeAPIClient.emptyNote(id: "pending")
    private var speakers: [NativeAPIClient.SpeakerDTO] = []
    private var applyingRemote = false
    private(set) var isReady = true
    private var baseBottomInset: CGFloat = KCDesign.Space.lg
    private var keyboardOverlap: CGFloat = 0
    private var isBodyEditing = false
    /// contentOffset before an edit; restored after UIKit/layout may clamp it to 0.
    private var pendingScrollAnchor: CGPoint?
    private var tapGesture: UITapGestureRecognizer!
    private let titlePlaceholderLabel = UILabel()
    private let bodyPlaceholderLabel = UILabel()
    private let tagsStrip = NoteEditorTagsStrip()
    private var bodyPlaceholderTopConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        let storage = NSTextStorage()
        let layout = NoteSpeakerRailLayoutManager()
        let container = NSTextContainer(size: .zero)
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        railLayoutManager = layout
        textView = NoteEditorTextView(frame: .zero, textContainer: container)
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setup() {
        precondition(Thread.isMainThread, "NativeNoteEditorView must be created on the main thread")
        backgroundColor = KCDesign.canvas

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.delegate = self
        textView.backgroundColor = KCDesign.canvas
        textView.textContainerInset = UIEdgeInsets(
            top: KCDesign.Space.md,
            left: KCDesign.Space.md,
            bottom: baseBottomInset,
            right: KCDesign.Space.md
        )
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        // Keyboard / accessory insets are applied manually in `applyKeyboard` —
        // never let the system add a second bottom inset on top (that makes
        // `scrollRangeToVisible` pin the caret line to the top of the viewport).
        textView.contentInsetAdjustmentBehavior = .never
        textView.adjustsFontForContentSizeCategory = true
        textView.allowsEditingTextAttributes = true
        textView.tintColor = KCDesign.accent
        textView.accessibilityLabel = String(localized: "Corpo da nota")
        textView.accessibilityHint = String(localized: "A primeira linha é o título")
        // Replace UIKit's pin-to-top `scrollRangeToVisible` with our minimal helper so
        // typing / Enter still follow the caret without jumping the viewport.
        textView.onRequestCaretScroll = { [weak self] in
            self?.scrollCaretVisible(animated: false)
        }
        addSubview(textView)

        titlePlaceholderLabel.translatesAutoresizingMaskIntoConstraints = false
        titlePlaceholderLabel.text = String(localized: "Título")
        titlePlaceholderLabel.font = UIFont.preferredFont(forTextStyle: .title1)
        titlePlaceholderLabel.textColor = .tertiaryLabel
        titlePlaceholderLabel.isUserInteractionEnabled = false
        titlePlaceholderLabel.adjustsFontForContentSizeCategory = true
        addSubview(titlePlaceholderLabel)

        bodyPlaceholderLabel.translatesAutoresizingMaskIntoConstraints = false
        bodyPlaceholderLabel.text = String(localized: "Comece a escrever…")
        bodyPlaceholderLabel.font = UIFont.preferredFont(forTextStyle: .body)
        bodyPlaceholderLabel.textColor = .tertiaryLabel
        bodyPlaceholderLabel.isUserInteractionEnabled = false
        bodyPlaceholderLabel.adjustsFontForContentSizeCategory = true
        bodyPlaceholderLabel.numberOfLines = 1
        addSubview(bodyPlaceholderLabel)

        tagsStrip.translatesAutoresizingMaskIntoConstraints = true
        tagsStrip.onTagsChange = { [weak self] tags in
            self?.applyTags(tags)
        }
        tagsStrip.onEditingChange = { [weak self] _ in
            self?.refreshEditingChrome()
        }
        // Scrolls with the title — lives inside the text view.
        textView.addSubview(tagsStrip)

        accessory.onAction = { [weak self] action in
            self?.handleAccessory(action)
        }
        // Formatting toolbar appears only after the user taps into the body (edit mode).
        textView.inputAccessoryView = nil

        let inset = textView.textContainerInset
        let bodyTop = bodyPlaceholderLabel.topAnchor.constraint(
            equalTo: titlePlaceholderLabel.bottomAnchor,
            constant: 12 + NoteEditorTagsStrip.preferredHeight + 8
        )
        bodyPlaceholderTopConstraint = bodyTop
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),

            titlePlaceholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: inset.top),
            titlePlaceholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: inset.left + 5),
            titlePlaceholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: textView.trailingAnchor, constant: -(inset.right)),

            bodyTop,
            bodyPlaceholderLabel.leadingAnchor.constraint(equalTo: titlePlaceholderLabel.leadingAnchor),
            bodyPlaceholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: textView.trailingAnchor, constant: -(inset.right)),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.delegate = self
        // Cancel the text view's caret move when we handle bible/speaker/check taps.
        tap.cancelsTouchesInView = true
        tapGesture = tap
        textView.addGestureRecognizer(tap)

        observeKeyboard()
        observeForegroundAppearance()
        refreshPlaceholders()
        repositionTagsStrip()
    }

    /// Re-assert dynamic colors after background snapshots / Bible-app round-trips.
    private func observeForegroundAppearance() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(handleForegroundAppearanceRefresh),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleForegroundAppearanceRefresh),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: NativeNoteEditorView, _) in
                view.refreshAppearanceForCurrentTraits(forceAttachments: true)
            }
        }
    }

    @objc private func handleForegroundAppearanceRefresh() {
        refreshAppearanceForCurrentTraits(forceAttachments: true)
    }

    /// Public entry for the note VC after returning from an external Bible app.
    func refreshAppearanceForCurrentTraits(forceAttachments: Bool = false) {
        refreshDynamicTextColors()
        titlePlaceholderLabel.textColor = .tertiaryLabel
        bodyPlaceholderLabel.textColor = .tertiaryLabel
        backgroundColor = KCDesign.canvas
        textView.backgroundColor = KCDesign.canvas
        if forceAttachments {
            forceRefreshAttachmentAppearances()
        } else {
            refreshAttachmentAppearances()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        repositionTagsStrip()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Window attachment is when overrideUserInterfaceStyle finally reaches the text view.
        guard window != nil else { return }
        refreshAppearanceForCurrentTraits(forceAttachments: true)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection)
            || textView.traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection)
        else { return }
        // Baked attachments + attributed title/body colors — rebuild for light/dark.
        // Background snapshots briefly flip traits; re-resolve so we never keep a stale bake.
        refreshAppearanceForCurrentTraits(forceAttachments: true)
    }

    /// Traits used to bake attachment chrome: prefer the text view's real traits, then the
    /// in-app Appearance override. Always returns a concrete `.light` / `.dark` style.
    private func speakerBakeTraits() -> UITraitCollection {
        var style = textView.traitCollection.userInterfaceStyle
        if style == .unspecified {
            style = traitCollection.userInterfaceStyle
        }
        if style == .unspecified {
            style = window?.traitCollection.userInterfaceStyle ?? .unspecified
        }
        style = SpeakerHeaderAttachment.resolvedBakeStyle(preferred: style)
        return SpeakerHeaderAttachment.bakeTraits(
            style: style,
            scale: textView.traitCollection.displayScale > 0
                ? textView.traitCollection.displayScale
                : UIScreen.main.scale
        )
    }

    private func refreshAttachmentAppearances() {
        refreshSpeakerHeaderAppearances(force: false)
        refreshBibleRefPillAppearances(force: false)
    }

    private func forceRefreshAttachmentAppearances() {
        refreshSpeakerHeaderAppearances(force: true)
        refreshBibleRefPillAppearances(force: true)
    }

    /// Re-stamp dynamic `UIColor.label` / `secondaryLabel` / bookmark on text runs.
    /// Background snapshots can leave TextKit with a once-resolved CGColor that no longer matches.
    private func refreshDynamicTextColors() {
        let storage = textView.textStorage
        guard storage.length > 0 else { return }
        storage.beginEditing()
        storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length), options: []) { attrs, range, _ in
            if attrs[.attachment] != nil { return }
            if attrs[NoteDocumentCodec.bibleRefKey] != nil { return }
            if let fg = attrs[.foregroundColor] as? UIColor {
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                if fg.getRed(&r, green: &g, blue: &b, alpha: &a), a < 0.01 { return }
            }
            if attrs[NoteDocumentCodec.listMarkerKey] as? Bool == true {
                storage.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: range)
                return
            }
            if attrs[NoteDocumentCodec.linkKey] != nil {
                storage.addAttribute(.foregroundColor, value: KCDesign.bookmark, range: range)
                return
            }
            storage.addAttribute(.foregroundColor, value: UIColor.label, range: range)
        }
        storage.endEditing()
        // Nudge layout so glyph colors rebuild against the current trait collection.
        textView.setNeedsDisplay()
        textView.layoutManager.invalidateLayout(
            forCharacterRange: NSRange(location: 0, length: storage.length),
            actualCharacterRange: nil
        )
        textView.layoutManager.ensureLayout(for: textView.textContainer)
    }

    /// Re-render every `SpeakerHeaderAttachment` for the text view's trait collection.
    private func refreshSpeakerHeaderAppearances(force: Bool) {
        let storage = textView.textStorage
        guard storage.length > 0 else { return }
        let inset = textView.textContainerInset
        let width = max(120, textView.bounds.width - inset.left - inset.right - textView.textContainer.lineFragmentPadding * 2)
        let traits = speakerBakeTraits()
        let style = SpeakerHeaderAttachment.resolvedBakeStyle(preferred: traits.userInterfaceStyle)
        var touched = false
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            guard let header = value as? SpeakerHeaderAttachment else { return }
            let w = max(header.image?.size.width ?? 0, width)
            if !force,
               header.image != nil,
               abs(header.renderedWidth - w) <= 1,
               header.renderedInterfaceStyle == style
            {
                return
            }
            header.refreshImage(width: w, traits: traits)
            touched = true
        }
        guard touched else { return }
        invalidateAttachmentDisplay()
    }

    /// Re-bake bible ref pills under the live text-view / Appearance traits (build-234).
    private func refreshBibleRefPillAppearances(force: Bool) {
        let storage = textView.textStorage
        guard storage.length > 0 else { return }
        let traits = speakerBakeTraits()
        let style = SpeakerHeaderAttachment.resolvedBakeStyle(preferred: traits.userInterfaceStyle)
        var touched = false
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            guard let pill = value as? BibleRefPillAttachment else { return }
            if !force, pill.image != nil, pill.renderedInterfaceStyle == style { return }
            pill.refreshImage(traits: traits)
            touched = true
        }
        guard touched else { return }
        invalidateAttachmentDisplay()
    }

    private func invalidateAttachmentDisplay() {
        let storage = textView.textStorage
        guard storage.length > 0 else { return }
        let full = NSRange(location: 0, length: storage.length)
        textView.layoutManager.invalidateLayout(forCharacterRange: full, actualCharacterRange: nil)
        textView.layoutManager.invalidateDisplay(forCharacterRange: full)
        textView.setNeedsDisplay()
    }

    private func refreshSpeakerRails() {
        railLayoutManager.rails = NoteDocumentCodec.speakerRailSpecs(
            in: textView.textStorage,
            speakers: speakers
        )
        // Force background redraw so rails grow/shrink with typed text.
        let length = textView.textStorage.length
        let containerWidth = textView.textContainer.size.width
        if length > 0, containerWidth > 1 {
            railLayoutManager.invalidateLayout(
                forCharacterRange: NSRange(location: 0, length: length),
                actualCharacterRange: nil
            )
            textView.layoutManager.ensureLayout(for: textView.textContainer)
        }
        textView.setNeedsDisplay()
    }

    private func observeKeyboard() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardFrameWillChange(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    @objc private func keyboardFrameWillChange(_ notification: Notification) {
        applyKeyboard(notification: notification, hiding: false)
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        applyKeyboard(notification: notification, hiding: true)
    }

    private func applyKeyboard(notification: Notification, hiding: Bool = false) {
        guard let userInfo = notification.userInfo,
              let endFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        else { return }
        let duration = (userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        let curveRaw = (userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt) ?? 7
        let options = UIView.AnimationOptions(rawValue: curveRaw << 16)

        let overlap: CGFloat
        if hiding {
            overlap = 0
        } else {
            let frameInView = convert(endFrame, from: nil)
            overlap = max(0, bounds.maxY - frameInView.minY)
        }

        keyboardOverlap = overlap
        // Accessory bar sits above the keyboard; add a little breathing room for the caret.
        let accessoryH = (textView.isFirstResponder && textView.inputAccessoryView != nil) ? max(accessory.bounds.height, 44) : 0
        let bottom = overlap + (overlap > 0 ? accessoryH + KCDesign.Space.md : 0)

        UIView.animate(withDuration: duration, delay: 0, options: options) {
            self.textView.contentInset.bottom = bottom
            self.textView.verticalScrollIndicatorInsets.bottom = bottom
            self.textView.textContainerInset.bottom = self.baseBottomInset + (overlap > 0 ? KCDesign.Space.sm : 0)
        } completion: { _ in
            self.scrollCaretVisible(animated: true)
        }
    }

    private func setEditingChrome(_ editing: Bool) {
        isBodyEditing = editing
        let next: UIView? = editing ? accessory : nil
        if textView.inputAccessoryView !== next {
            textView.inputAccessoryView = next
            textView.reloadInputViews()
        }
    }

    /// Toolbar only while editing the body — hidden for title / tags (TF210).
    private func refreshEditingChrome() {
        let show = textView.isFirstResponder && !isCaretInTitle() && !tagsStrip.isEditingTags
        setEditingChrome(show)
    }

    private func isCaretInTitle() -> Bool {
        let attrs = paragraphStartAttributes()
        if (attrs[NoteDocumentCodec.blockIdKey] as? String) == "title" { return true }
        let range = paragraphRange()
        return range.location == 0 && (attrs[NoteDocumentCodec.blockTypeKey] as? String) == "heading"
    }

    private func applyTags(_ tags: [String]) {
        documentBase.tags = tags
        emitChange()
    }

    private func repositionTagsStrip() {
        let inset = textView.textContainerInset
        let width = max(0, textView.bounds.width - inset.left - inset.right - 5)
        let height = NoteEditorTagsStrip.preferredHeight
        var y = inset.top + 28
        if textView.textStorage.length > 0 {
            let titlePara = (textView.textStorage.string as NSString).paragraphRange(
                for: NSRange(location: 0, length: 0)
            )
            let glyphRange = textView.layoutManager.glyphRange(
                forCharacterRange: titlePara,
                actualCharacterRange: nil
            )
            let rect = textView.layoutManager.boundingRect(
                forGlyphRange: glyphRange,
                in: textView.textContainer
            )
            y = inset.top + rect.maxY + 4
        }
        tagsStrip.frame = CGRect(x: inset.left + 5, y: y, width: width, height: height)
    }

    /// Keep the caret on-screen with the smallest possible contentOffset change.
    /// Never use `scrollRangeToVisible` here: with a large keyboard+accessory
    /// `contentInset.bottom` it pins the caret line to the top of the viewport
    /// and leaves a blank gap above the toolbar (Enter / Backspace jump).
    private func scrollCaretVisible(animated: Bool) {
        guard textView.isFirstResponder || testing_forceCaretScroll else { return }
        restoreScrollAnchorIfNeeded()
        applyMinimalCaretScroll(animated: animated)
    }

    /// Test seam: allow caret-scroll without first responder (AppTests host).
    var testing_forceCaretScroll = false

    private func captureScrollAnchor() {
        let offset = textView.contentOffset
        pendingScrollAnchor = offset
        // Hold offset steady while TextKit briefly reports a tiny contentSize (UIKit
        // would otherwise clamp to 0 and our restore would run too late / on a 0 max).
        textView.stickyContentOffset = offset
    }

    private func clearScrollAnchor() {
        pendingScrollAnchor = nil
        textView.stickyContentOffset = nil
    }

    /// Put the pre-edit offset back (clamped to measured content height), then minimal-scroll.
    private func restoreScrollAnchorIfNeeded() {
        guard let anchor = pendingScrollAnchor else {
            textView.stickyContentOffset = nil
            return
        }
        pendingScrollAnchor = nil
        textView.stickyContentOffset = nil
        textView.layoutManager.ensureLayout(for: textView.textContainer)
        textView.layoutIfNeeded()
        let insets = textView.adjustedContentInset
        let minY = -insets.top
        let contentH = measuredContentHeight()
        let maxY = max(minY, contentH - textView.bounds.height + insets.bottom)
        let y = min(max(anchor.y, minY), maxY)
        if abs(textView.contentOffset.y - y) > 0.5 {
            textView.setContentOffset(CGPoint(x: anchor.x, y: y), animated: false)
        }
    }

    /// TextKit used-rect height — more trustworthy than `contentSize` mid-mutation.
    private func measuredContentHeight() -> CGFloat {
        let used = textView.layoutManager.usedRect(for: textView.textContainer)
        let extra = textView.layoutManager.extraLineFragmentUsedRect
        let bottom = max(used.maxY, extra.height > 0 ? extra.maxY : 0)
        let fromLayout = bottom + textView.textContainerInset.top + textView.textContainerInset.bottom
        return max(textView.contentSize.height, fromLayout)
    }

    /// Caret rect in view bounds from layoutManager (reliable without a key window).
    private func caretRectInBoundsForScroll() -> CGRect? {
        textView.layoutManager.ensureLayout(for: textView.textContainer)
        let storage = textView.textStorage
        let inset = textView.textContainerInset
        guard storage.length > 0 else {
            guard let selected = textView.selectedTextRange else { return nil }
            let rect = textView.caretRect(for: selected.start)
            return rect.isNull ? nil : rect
        }

        let loc = min(max(0, textView.selectedRange.location), storage.length)
        let ns = storage.string as NSString
        let endsWithNewline = ns.length > 0 && ns.character(at: ns.length - 1) == 10
        let extra = textView.layoutManager.extraLineFragmentUsedRect

        let contentY: CGFloat
        let height: CGFloat
        if loc >= storage.length, endsWithNewline || extra.height > 0 {
            if extra.height > 0 {
                contentY = inset.top + extra.minY
                height = max(extra.height, 1)
            } else {
                let lastGlyph = textView.layoutManager.glyphIndexForCharacter(at: storage.length - 1)
                var lineRange = NSRange()
                let lineRect = textView.layoutManager.lineFragmentUsedRect(
                    forGlyphAt: lastGlyph,
                    effectiveRange: &lineRange
                )
                let lineH = ceil((textView.typingAttributes[.font] as? UIFont)?.lineHeight ?? 22)
                contentY = inset.top + lineRect.maxY
                height = lineH
            }
        } else {
            let charIndex = min(loc, storage.length - 1)
            let glyphIndex = textView.layoutManager.glyphIndexForCharacter(at: charIndex)
            var lineRange = NSRange()
            let lineRect = textView.layoutManager.lineFragmentUsedRect(
                forGlyphAt: glyphIndex,
                effectiveRange: &lineRange
            )
            contentY = inset.top + lineRect.minY
            height = max(lineRect.height, 1)
        }

        return CGRect(
            x: inset.left,
            y: contentY - textView.contentOffset.y,
            width: 2,
            height: height
        )
    }

    private func applyMinimalCaretScroll(animated: Bool) {
        textView.layoutManager.ensureLayout(for: textView.textContainer)
        textView.layoutIfNeeded()

        guard let caret = caretRectInBoundsForScroll() else { return }
        guard caret.origin.x.isFinite, caret.origin.y.isFinite, caret.height.isFinite, !caret.isNull else { return }

        let insets = textView.adjustedContentInset
        let targetY = NoteEditorCaretScroll.contentOffsetY(
            caretRectInBounds: caret,
            boundsHeight: textView.bounds.height,
            contentInset: insets,
            contentSizeHeight: measuredContentHeight(),
            currentOffsetY: textView.contentOffset.y
        )
        let current = textView.contentOffset
        guard abs(targetY - current.y) > 0.5 else { return }

        let next = CGPoint(x: current.x, y: targetY)
        let apply = {
            self.textView.stickyContentOffset = nil
            self.textView.setContentOffset(next, animated: false)
        }
        if animated {
            UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                apply()
            }
        } else {
            UIView.performWithoutAnimation(apply)
        }
    }

    /// Load / replace the document currently shown.
    func pushNote(_ note: NativeAPIClient.NoteDocument, speakers: [NativeAPIClient.SpeakerDTO] = [], readOnly: Bool = false) {
        precondition(Thread.isMainThread)
        documentBase = note
        self.speakers = speakers
        applyingRemote = true
        let attributed = NoteDocumentCodec.attributedString(from: note, speakers: speakers)
        // Prefer textStorage mutation over attributedText reassign when possible so we
        // don't thrash selection — but a full load must replace content once.
        textView.textStorage.setAttributedString(attributed)
        textView.selectedRange = NSRange(location: 0, length: 0)
        textView.typingAttributes = typingAttributesForCaret()
        textView.isEditable = !readOnly
        tagsStrip.isUserInteractionEnabled = !readOnly
        tagsStrip.setTags(note.tags)
        applyingRemote = false
        isReady = true
        // Attachments may have been baked offline / under the wrong traits — sync to this view.
        refreshAttachmentAppearances()
        refreshSpeakerRails()
        refreshPlaceholders()
        repositionTagsStrip()
    }

    /// Refresh the in-memory speaker catalog without rewriting the note body.
    func updateSpeakers(_ speakers: [NativeAPIClient.SpeakerDTO]) {
        precondition(Thread.isMainThread)
        self.speakers = speakers
        refreshSpeakerRails()
    }

    func currentDocument() -> NativeAPIClient.NoteDocument {
        precondition(Thread.isMainThread)
        // Prefer textStorage — UITextView.attributedText can drop custom keys (speakerBodyKey / blockType).
        return NoteDocumentCodec.document(from: textView.textStorage, base: documentBase)
    }

    func insertBibleRef(_ ref: NoteDocumentCodec.BibleRefPayload) {
        precondition(Thread.isMainThread)
        var base = textView.typingAttributes
        base[NoteDocumentCodec.blockTypeKey] = currentBlockType() == "speakerSection" ? "paragraph" : currentBlockType()
        base[NoteDocumentCodec.blockIdKey] = currentBlockId()
        let piece = NoteDocumentCodec.bibleRefPill(payload: ref, base: base)
        textView.textStorage.replaceCharacters(in: textView.selectedRange, with: piece)
        let end = textView.selectedRange.location + piece.length
        textView.selectedRange = NSRange(location: end, length: 0)
        textView.typingAttributes = baseTypingAttributes()
        emitChange()
        refreshPlaceholders()
        scrollCaretVisible(animated: true)
    }

    func insertSpeakerSection(speakerId: String, name: String) {
        precondition(Thread.isMainThread)
        // Model-first (web `insertSpeakerSection`): never invent blank speakerSection
        // paragraphs from separator newlines, always seed one empty body child, ensure
        // a tap target after the section when it is last.
        var doc = currentDocument()
        let anchorId = currentBlockId()
        let result = SpeakerSectionEditing.insertSpeakerBlock(
            into: doc,
            speakerId: speakerId,
            speakerName: name,
            afterBlockId: anchorId
        )
        doc = result.document
        documentBase = doc
        applyingRemote = true
        let attributed = NoteDocumentCodec.attributedString(from: doc, speakers: speakers)
        textView.textStorage.setAttributedString(attributed)
        placeCaretInSpeakerBody(bodyId: result.focusBodyId, sectionId: result.sectionId)
        applyingRemote = false
        emitChange()
        refreshSpeakerRails()
        refreshPlaceholders()
        _ = textView.becomeFirstResponder()
        refreshEditingChrome()
        scrollCaretVisible(animated: true)
    }

    /// Reassign the catalog speaker for an existing section (header is not typed text).
    func renameSpeakerSection(sectionId: String, speakerId: String, name: String) {
        precondition(Thread.isMainThread)
        var doc = currentDocument()
        guard let idx = doc.body.blocks.firstIndex(where: { $0.id == sectionId && $0.type == "speakerSection" })
        else { return }
        doc.body.blocks[idx].speakerId = speakerId
        doc.body.blocks[idx].title = name
        let bodyId = doc.body.blocks[idx].blocks?.first?.id
        applyDocument(doc, preferBlockId: bodyId ?? sectionId)
        if let bodyId {
            placeCaretInSpeakerBody(bodyId: bodyId, sectionId: sectionId)
        } else {
            moveCaretOffSpeakerHeaderIfNeeded()
        }
    }

    // MARK: - UITextViewDelegate

    func textViewDidBeginEditing(_ textView: UITextView) {
        ensureTypingAttributes()
        refreshEditingChrome()
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        refreshEditingChrome()
    }

    func textViewDidChange(_ textView: UITextView) {
        guard !applyingRemote else { return }
        if textView.textStorage.length == 0 {
            reseedEmptyDocument()
            refreshPlaceholders()
            return
        }
        // Header is an attachment — never treat it as typed text. Body keeps speakerBodyKey.
        if paragraphBlockType() == "speakerSection" {
            moveCaretOffSpeakerHeaderIfNeeded()
        } else if caretIsInsideSpeakerSection() {
            normalizeSpeakerBodyParagraphAttributes()
            textView.typingAttributes = typingAttributesForSpeakerBody()
        } else {
            ensureTypingAttributes()
        }
        emitChange()
        refreshSpeakerRails()
        refreshPlaceholders()
        scrollCaretVisible(animated: false)
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        if !applyingRemote {
            moveCaretOffSpeakerHeaderIfNeeded()
            ensureTypingAttributes()
            refreshEditingChrome()
        }
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        // Snapshot scroll before UIKit/TextKit can clamp contentOffset during the edit.
        captureScrollAnchor()
        // Never let the keyboard mutate the non-editable speaker header (attachment or
        // its trailing "\n"). Bounce into the body; do not also run exit/continue — web
        // Enter-on-header only moves into the seeded body.
        if rangeIntersectsSpeakerHeader(range) || paragraphBlockType() == "speakerSection" {
            _ = moveCaretIntoSpeakerBodyAfterHeader()
            clearScrollAnchor()
            return false
        }

        if caretIsInsideSpeakerSection(), paragraphBlockType() != "speakerSection" {
            textView.typingAttributes = typingAttributesForSpeakerBody()
        } else {
            ensureTypingAttributes()
        }

        if Self.isNewlineReplacement(text) {
            let type = paragraphBlockType()
            // Caret on header attachment: jump into first body (or exit if collapsed-only).
            if type == "speakerSection" {
                if moveCaretIntoSpeakerBodyAfterHeader() {
                    return false
                }
            }
            let inside = caretIsInsideSpeakerSection()
            let decision = SpeakerEnterDecision.decide(
                blockType: paragraphBlockType(),
                insideSpeaker: inside,
                paragraphEmpty: isCurrentParagraphVisuallyEmpty(),
                isLastBodyOfSection: isLastBodyParagraphOfSpeakerSection()
            )
            switch decision {
            case .insertBodyFromHeader:
                // Header is non-editable; treat like continue/seeded body.
                insertContinuingSpeakerBodyParagraph()
                return false
            case .continueInSection:
                insertContinuingSpeakerBodyParagraph()
                return false
            case .demoteListToParagraph:
                applyBlockType("paragraph", preserveChecked: false)
                scrollCaretVisible(animated: true)
                return false
            case .exitSection:
                exitSpeakerSection()
                return false
            case .continueList(let listType):
                insertContinuingListItem(listType: listType)
                return false
            case .defaultNewline:
                if inside {
                    insertContinuingSpeakerBodyParagraph()
                    return false
                }
                // Manual insert so the new outside paragraph never inherits
                // speaker/list hanging indent from UIKit's attribute copy (TF194 #1).
                insertContinuingOutsideParagraph()
                return false
            }
        }

        if caretIsInsideSpeakerSection(), paragraphBlockType() != "speakerSection" {
            textView.typingAttributes = typingAttributesForSpeakerBody()
        }

        // Backspace / delete — custom empty-line + reference-pill path (web onMerge / arm→delete).
        // Empty plain lines must merge in ONE press (skip the ZWSP placeholder step).
        // Empty list markers keep 2 presses (demote, then merge). Pills keep select→delete.
        if text.isEmpty {
            if handleCustomBackspace(proposedRange: range) {
                return false
            }
        }

        // TF210: @ and / are ordinary characters — speaker / reference only via toolbar.
        return true
    }

    /// Custom Backspace. Returns `true` when the deletion was fully handled (caller returns false).
    @discardableResult
    private func handleCustomBackspace(proposedRange range: NSRange) -> Bool {
        // Reference pills: first press selects, second deletes (do not treat as empty-line merge).
        if let pillRange = bibleRefAttachmentRange(intersecting: range) {
            let selected = textView.selectedRange
            let alreadyArmed = selected.length > 0
                && NSIntersectionRange(selected, pillRange).length == pillRange.length
            if alreadyArmed {
                // Second press — let UIKit / testing_deleteBackward remove the attachment.
                return false
            }
            textView.selectedRange = pillRange
            clearScrollAnchor()
            return true
        }

        // Only intercept empty-line merges / list demotes for collapsed carets (or deletes
        // that land inside the current visually-empty paragraph).
        let caret = textView.selectedRange
        let para = paragraphRange()
        let beforeCaret = caret.location > 0 ? caret.location - 1 : caret.location
        let touchesCurrentPara = NSIntersectionRange(range, para).length > 0
            || (caret.length == 0 && range.location + range.length == para.location)
            || (caret.length == 0 && NSLocationInRange(beforeCaret, para))
        guard touchesCurrentPara, isCurrentParagraphVisuallyEmpty() else {
            return false
        }

        let type = paragraphBlockType()
        if type == "bullet" || type == "numbered" || type == "check" || type == "quote" {
            // First press removes the bullet/marker (demote). Second press merges the plain line.
            applyBlockType("paragraph", preserveChecked: false)
            scrollCaretVisible(animated: true)
            return true
        }

        // Never merge away the title / speaker header chrome via this path.
        if type == "speakerSection" || (type == "heading" && para.location == 0) {
            return false
        }

        return mergeEmptyPlainParagraphOnBackspace()
    }

    /// Range of a bible-ref attachment touched by a proposed delete, if any.
    /// Also treats the soft ZWSP pads around pills as part of the arm→delete gesture.
    private func bibleRefAttachmentRange(intersecting range: NSRange) -> NSRange? {
        let storage = textView.textStorage
        guard storage.length > 0, range.length > 0 else { return nil }
        let ns = storage.string as NSString

        func pillRange(at index: Int) -> NSRange? {
            guard index >= 0, index < storage.length else { return nil }
            var effective = NSRange(location: index, length: 1)
            let attrs = storage.attributes(at: index, effectiveRange: &effective)
            if attrs[.attachment] is BibleRefPillAttachment || attrs[NoteDocumentCodec.bibleRefKey] != nil {
                return effective
            }
            return nil
        }

        // Direct hit on the attachment character.
        if let hit = pillRange(at: range.location) { return hit }

        // Soft ZWSP pad immediately before/after the pill (bibleRefPill wraps pads).
        let candidates = [range.location, range.location - 1, range.location + 1]
        for raw in candidates {
            guard raw >= 0, raw < ns.length else { continue }
            let ch = ns.substring(with: NSRange(location: raw, length: 1))
            guard ch == "\u{200B}" else { continue }
            if let after = pillRange(at: raw + 1) { return after }
            if raw > 0, let before = pillRange(at: raw - 1) { return before }
        }
        return nil
    }

    /// Join an empty plain paragraph with the previous line in one Backspace (web `onMerge`).
    /// Skips the ZWSP-only first step that made empty lines need two presses.
    @discardableResult
    private func mergeEmptyPlainParagraphOnBackspace() -> Bool {
        let storage = textView.textStorage
        let para = paragraphRange()
        guard para.location > 0, para.length >= 0, storage.length >= NSMaxRange(para) else {
            clearScrollAnchor()
            return false
        }
        // Delete only this empty paragraph (incl. its trailing `\n` when present). Keep the
        // previous paragraph's terminator so "hello\n·\nworld" → "hello\nworld", not "helloworld".
        let caret = max(0, para.location - 1)
        storage.replaceCharacters(in: para, with: "")
        let loc = min(caret, storage.length)
        textView.selectedRange = NSRange(location: loc, length: 0)
        textView.typingAttributes = typingAttributesForCaret()
        emitChange()
        refreshPlaceholders()
        refreshSpeakerRails()
        scrollCaretVisible(animated: true)
        return true
    }

    private func emitChange() {
        let doc = currentDocument()
        documentBase = doc
        delegate?.nativeNoteEditorDidChange(self, document: doc)
    }

    // MARK: - Accessory

    private func handleAccessory(_ action: NoteEditorAccessoryBar.Action) {
        switch action {
        case .bold: toggleBoldMark()
        case .italic: toggleItalicMark()
        case .heading: toggleHeading()
        case .bullet: toggleBullet()
        case .numbered: toggleNumbered()
        case .check: toggleCheck()
        case .quote: toggleQuote()
        case .underline: toggleUnderlineMark()
        case .strike: toggleStrikeMark()
        case .bibleRef: presentBibleRefPicker()
        case .speaker: presentSpeakerPicker()
        }
    }

    // MARK: - Formatting

    private func baseTypingAttributes() -> [NSAttributedString.Key: Any] {
        let rawType = currentBlockType()
        if rawType == "heading" {
            return NoteDocumentCodec.baseAttributesPublic(
                type: "heading",
                id: currentBlockId(),
                checked: nil,
                speakerId: nil,
                speakers: [:]
            )
        }
        if rawType == "speakerSection" {
            // Header is non-editable chrome — typing attrs are body-inside-section.
            return SpeakerSectionEditing.bodyTypingAttributes()
        }
        if caretIsInsideSpeakerSection() {
            return typingAttributesForSpeakerBody(blockType: rawType)
        }
        return NoteDocumentCodec.baseAttributesPublic(
            type: rawType,
            id: currentBlockId(),
            checked: rawType == "check" ? false : nil,
            speakerId: nil,
            speakers: [:]
        )
    }

    /// Typing attrs inside a speaker body — keep list/quote kinds (TF200 #1).
    private func typingAttributesForSpeakerBody(blockType: String? = nil) -> [NSAttributedString.Key: Any] {
        let type = blockType ?? paragraphBlockType()
        let id = currentBlockId()
        if type == "bullet" || type == "numbered" || type == "check" || type == "quote" {
            return SpeakerSectionEditing.listTypingAttributes(
                type: type,
                blockId: id,
                inSpeakerSection: true
            )
        }
        return SpeakerSectionEditing.bodyTypingAttributes(blockId: id)
    }

    private func typingAttributesForCaret() -> [NSAttributedString.Key: Any] {
        if textView.textStorage.length == 0 {
            return NoteDocumentCodec.baseAttributesPublic(
                type: "heading",
                id: "title",
                checked: nil,
                speakerId: nil,
                speakers: [:]
            )
        }
        return baseTypingAttributes()
    }

    /// Guarantee font / paragraphStyle / block metadata match the load path.
    private func ensureTypingAttributes() {
        let typing = textView.typingAttributes
        let missingBlock = typing[NoteDocumentCodec.blockTypeKey] == nil
        let missingFont = typing[.font] == nil
        let missingPara = typing[.paragraphStyle] == nil
        let typingType = typing[NoteDocumentCodec.blockTypeKey] as? String
        let caretType = paragraphBlockType()
        // Title → body (and list promote) must not keep stale heading typing attrs —
        // direct textStorage inserts use typingAttributes as-is (TF194 list Enter).
        let typeMismatch = typingType != nil && typingType != caretType
            && caretType != "speakerSection"
        guard missingBlock || missingFont || missingPara || typeMismatch else { return }
        textView.typingAttributes = typingAttributesForCaret()
    }

    private func reseedEmptyDocument() {
        applyingRemote = true
        var empty = NativeAPIClient.emptyNote(id: documentBase.id)
        empty.happenedAt = documentBase.happenedAt
        empty.tags = documentBase.tags
        empty.noteSpeakerId = documentBase.noteSpeakerId
        empty.visibility = documentBase.visibility
        let attributed = NoteDocumentCodec.attributedString(from: empty, speakers: speakers)
        textView.textStorage.setAttributedString(attributed)
        textView.selectedRange = NSRange(location: 0, length: 0)
        textView.typingAttributes = typingAttributesForCaret()
        applyingRemote = false
        documentBase = empty
        emitChange()
        refreshSpeakerRails()
        refreshPlaceholders()
    }

    private func insertContinuingSpeakerBodyParagraph() {
        captureScrollAnchor()
        let result = SpeakerSectionEditing.insertContinuingBodyParagraph(
            in: textView.textStorage,
            at: textView.selectedRange.location
        )
        textView.selectedRange = NSRange(location: result.caret, length: 0)
        textView.typingAttributes = result.typingAttributes
        emitChange()
        refreshSpeakerRails()
        scrollCaretVisible(animated: true)
    }

    private func insertContinuingOutsideParagraph() {
        captureScrollAnchor()
        let result = SpeakerSectionEditing.insertContinuingOutsideParagraph(
            in: textView.textStorage,
            at: textView.selectedRange.location
        )
        textView.selectedRange = NSRange(location: result.caret, length: 0)
        textView.typingAttributes = result.typingAttributes
        emitChange()
        refreshSpeakerRails()
        scrollCaretVisible(animated: true)
    }

    private func insertContinuingListItem(listType: String) {
        captureScrollAnchor()
        let range = paragraphRange()
        let number = numberedIndex(
            forParagraphStartingAt: range.location,
            promotingToNumbered: listType == "numbered"
        ) + (listType == "numbered" ? 1 : 0)
        let marker = NoteDocumentCodec.listMarkerString(
            type: listType,
            checked: listType == "check" ? false : nil,
            number: max(number, 1)
        ) ?? "•\u{00A0}"
        let inSection = caretIsInsideSpeakerSection()
            || NoteDocumentCodec.isSpeakerBody(paragraphStartAttributes())
        let result = SpeakerSectionEditing.insertContinuingListParagraph(
            in: textView.textStorage,
            at: textView.selectedRange.location,
            listType: listType,
            marker: marker,
            inSpeakerSection: inSection,
            listNumber: max(number, 1)
        )
        textView.selectedRange = NSRange(location: result.caret, length: 0)
        textView.typingAttributes = result.typingAttributes
        emitChange()
        refreshSpeakerRails()
        scrollCaretVisible(animated: true)
    }

    /// Hardware keyboards sometimes send `\r` / `\r\n` instead of `\n`.
    nonisolated static func isNewlineReplacement(_ text: String) -> Bool {
        text == "\n" || text == "\r" || text == "\r\n"
    }

    /// Attributes at the start of the caret's paragraph (source of truth for block type).
    private func paragraphStartAttributes() -> [NSAttributedString.Key: Any] {
        let storage = textView.textStorage
        guard storage.length > 0 else { return [:] }
        let para = paragraphRange()
        let loc = min(max(para.location, 0), storage.length - 1)
        return storage.attributes(at: loc, effectiveRange: nil)
    }

    /// Block type from the paragraph start — not the caret character (which can be demoted mid-name).
    private func paragraphBlockType() -> String {
        (paragraphStartAttributes()[NoteDocumentCodec.blockTypeKey] as? String) ?? "paragraph"
    }

    /// True when the caret sits in a speaker header or any body paragraph of that section.
    private func caretIsInsideSpeakerSection() -> Bool {
        let attrs = paragraphStartAttributes()
        if (attrs[NoteDocumentCodec.blockTypeKey] as? String) == "speakerSection" { return true }
        // After double-Enter exit, body paragraphs lose `speakerBodyKey`.
        return NoteDocumentCodec.isSpeakerBody(attrs)
    }

    /// Re-stamp speakerBodyKey (+ inset for plain body) on the body paragraph UIKit may have
    /// inserted bare. Must not demote bullet/numbered/check/quote back to paragraph (TF200 #1).
    private func normalizeSpeakerBodyParagraphAttributes() {
        let storage = textView.textStorage
        let para = paragraphRange()
        guard para.length > 0, storage.length >= NSMaxRange(para) else { return }
        let id = currentBlockId()
        let currentType = paragraphBlockType()
        let isListLike = currentType == "bullet" || currentType == "numbered"
            || currentType == "check" || currentType == "quote"
        let body = isListLike
            ? SpeakerSectionEditing.listTypingAttributes(
                type: currentType,
                blockId: id,
                inSpeakerSection: true
            )
            : SpeakerSectionEditing.bodyTypingAttributes(blockId: id)
        storage.enumerateAttributes(in: para, options: []) { attrs, sub, _ in
            if (attrs[NoteDocumentCodec.blockTypeKey] as? String) == "speakerSection" { return }
            var next = attrs
            let runType = (attrs[NoteDocumentCodec.blockTypeKey] as? String) ?? currentType
            let preserve = runType == "bullet" || runType == "numbered"
                || runType == "check" || runType == "quote"
            next[NoteDocumentCodec.blockTypeKey] = preserve ? runType : "paragraph"
            next[NoteDocumentCodec.blockIdKey] = id
            next[NoteDocumentCodec.speakerBodyKey] = true
            if attrs[NoteDocumentCodec.listMarkerKey] as? Bool == true {
                // Keep marker glyph styling; only stamp membership keys above.
            } else if let style = body[.paragraphStyle] {
                next[.paragraphStyle] = style
            }
            storage.setAttributes(next, range: sub)
        }
    }

    private func enclosingSpeakerSectionStart() -> Int? {
        let storage = textView.textStorage
        guard storage.length > 0 else { return nil }
        let loc = min(textView.selectedRange.location, max(0, storage.length - 1))
        let attrsAtCaret = storage.attributes(at: loc, effectiveRange: nil)
        let onHeader = (attrsAtCaret[NoteDocumentCodec.blockTypeKey] as? String) == "speakerSection"
        let inBody = NoteDocumentCodec.isSpeakerBody(attrsAtCaret)
            && (attrsAtCaret[NoteDocumentCodec.blockTypeKey] as? String) != "speakerSection"
        guard onHeader || inBody else { return nil }
        let ns = storage.string as NSString
        var cursor = loc
        while cursor >= 0 {
            let para = ns.paragraphRange(for: NSRange(location: cursor, length: 0))
            let attrs: [NSAttributedString.Key: Any]
            if para.length > 0 {
                attrs = storage.attributes(at: para.location, effectiveRange: nil)
            } else if storage.length > para.location {
                attrs = storage.attributes(at: min(para.location, storage.length - 1), effectiveRange: nil)
            } else {
                attrs = [:]
            }
            if (attrs[NoteDocumentCodec.blockTypeKey] as? String) == "speakerSection" {
                return para.location
            }
            if para.location == 0 { break }
            cursor = para.location - 1
        }
        return nil
    }

    private func isCurrentParagraphVisuallyEmpty() -> Bool {
        let storage = textView.textStorage
        let para = paragraphRange()
        guard para.length > 0 else { return true }
        // Paragraphs that are only a list marker (+ ZWSP) count as empty (web empty ul/ol).
        var onlyMarker = true
        storage.enumerateAttributes(in: para, options: []) { attrs, sub, stop in
            let chunk = (storage.string as NSString).substring(with: sub)
                .replacingOccurrences(of: "\u{200B}", with: "")
                .replacingOccurrences(of: "\u{00A0}", with: "")
                .replacingOccurrences(of: "\n", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if chunk.isEmpty { return }
            if attrs[NoteDocumentCodec.listMarkerKey] as? Bool == true { return }
            onlyMarker = false
            stop.pointee = true
        }
        if onlyMarker { return true }

        var text = (storage.string as NSString).substring(with: para)
        text = text
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip common list markers left as display glyphs.
        let markers = ["•", "☐", "☑"]
        for marker in markers where text.hasPrefix(marker) {
            text = String(text.dropFirst(marker.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let numbered = text.range(of: #"^\d+\.\s*"#, options: .regularExpression) {
            text.removeSubrange(numbered)
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text.isEmpty
    }

    private func isLastBodyParagraphOfSpeakerSection() -> Bool {
        let storage = textView.textStorage
        let ns = storage.string as NSString
        let para = paragraphRange()
        let after = NSMaxRange(para)
        if after >= storage.length { return true }
        let nextPara = ns.paragraphRange(for: NSRange(location: after, length: 0))
        guard nextPara.location < storage.length else { return true }
        let attrs = storage.attributes(at: nextPara.location, effectiveRange: nil)
        // Next speaker header ⇒ current body line is the last of this section.
        if (attrs[NoteDocumentCodec.blockTypeKey] as? String) == "speakerSection" { return true }
        // Another body paragraph still inside the same section.
        if NoteDocumentCodec.isSpeakerBody(attrs) { return false }
        return true
    }

    /// Remove the empty trailing body line (web: only if >1 children) and place a line after the section.
    private func exitSpeakerSection() {
        let bodyCount = countSpeakerBodyParagraphs(containingCaret: true)
        let result = SpeakerSectionEditing.exitSection(
            in: textView.textStorage,
            emptyBodyRange: paragraphRange(),
            removeEmptyBody: bodyCount > 1
        )
        textView.selectedRange = NSRange(location: result.caret, length: 0)
        textView.typingAttributes = result.typingAttributes
        emitChange()
        refreshSpeakerRails()
        scrollCaretVisible(animated: true)
    }

    private func countSpeakerBodyParagraphs(containingCaret: Bool) -> Int {
        _ = containingCaret
        guard let start = enclosingSpeakerSectionStart() else { return 0 }
        let storage = textView.textStorage
        let ns = storage.string as NSString
        var count = 0
        var cursor = start
        while cursor < ns.length {
            let para = ns.paragraphRange(for: NSRange(location: cursor, length: 0))
            let attrs = storage.attributes(at: min(para.location, storage.length - 1), effectiveRange: nil)
            if para.location > start, (attrs[NoteDocumentCodec.blockTypeKey] as? String) == "speakerSection" {
                break
            }
            if NoteDocumentCodec.isSpeakerBody(attrs),
               (attrs[NoteDocumentCodec.blockTypeKey] as? String) != "speakerSection"
            {
                count += 1
            }
            let next = NSMaxRange(para)
            if next <= cursor { break }
            cursor = next
        }
        return count
    }

    private func rangeIntersectsSpeakerHeader(_ range: NSRange) -> Bool {
        let storage = textView.textStorage
        guard storage.length > 0 else { return false }
        let start = max(0, range.location)
        let end = min(storage.length, NSMaxRange(range))
        if start >= end {
            // Insertion point — reject if caret sits on the attachment character
            // or anywhere in the header paragraph (incl. its trailing "\n").
            let loc = min(start, storage.length - 1)
            if NoteDocumentCodec.speakerHeaderAttachment(
                in: storage.attributes(at: loc, effectiveRange: nil)
            ) != nil {
                return true
            }
            let para = (storage.string as NSString).paragraphRange(for: NSRange(location: loc, length: 0))
            let startAttrs = storage.attributes(at: min(para.location, storage.length - 1), effectiveRange: nil)
            return NoteDocumentCodec.speakerHeaderAttachment(in: startAttrs) != nil
                || (startAttrs[NoteDocumentCodec.blockTypeKey] as? String) == "speakerSection"
        }
        var hits = false
        storage.enumerateAttribute(.attachment, in: NSRange(location: start, length: end - start)) { value, _, stop in
            if value is SpeakerHeaderAttachment {
                hits = true
                stop.pointee = true
            }
        }
        return hits
    }

    private func moveCaretOffSpeakerHeaderIfNeeded() {
        guard textView.textStorage.length > 0 else { return }
        // Entire header paragraph is chrome — including the trailing "\n" that
        // `appendLine` stamps with the body's blockId (still part of this paragraph).
        if paragraphBlockType() == "speakerSection" {
            _ = moveCaretIntoSpeakerBodyAfterHeader()
            return
        }
        let storage = textView.textStorage
        let loc = min(textView.selectedRange.location, storage.length - 1)
        let attrs = storage.attributes(at: loc, effectiveRange: nil)
        guard NoteDocumentCodec.speakerHeaderAttachment(in: attrs) != nil else { return }
        _ = moveCaretIntoSpeakerBodyAfterHeader()
    }

    @discardableResult
    private func moveCaretIntoSpeakerBodyAfterHeader() -> Bool {
        let storage = textView.textStorage
        let header = paragraphRange()
        // If caret is already past the header paragraph, don't bounce backwards.
        let caret = textView.selectedRange.location
        let after = caret > NSMaxRange(header) ? caret : NSMaxRange(header)
        if after < storage.length {
            let next = (storage.string as NSString).paragraphRange(for: NSRange(location: after, length: 0))
            let attrs = storage.attributes(at: min(next.location, storage.length - 1), effectiveRange: nil)
            if NoteDocumentCodec.isSpeakerBody(attrs),
               (attrs[NoteDocumentCodec.blockTypeKey] as? String) != "speakerSection"
            {
                textView.selectedRange = NSRange(location: next.location, length: 0)
                textView.typingAttributes = SpeakerSectionEditing.bodyTypingAttributes(
                    blockId: (attrs[NoteDocumentCodec.blockIdKey] as? String) ?? NoteDocumentCodec.newId()
                )
                return true
            }
        }
        // No body (collapsed): place caret after the section.
        textView.selectedRange = NSRange(location: min(NSMaxRange(header), storage.length), length: 0)
        textView.typingAttributes = SpeakerSectionEditing.outsideTypingAttributes()
        return true
    }

    /// Land inside a speaker body paragraph — never on the body's leading "\n", which
    /// still belongs to the previous (header) paragraph in NSString paragraph ranges.
    private func placeCaretInSpeakerBody(bodyId: String, sectionId: String) {
        if let loc = contentLocation(forBlockId: bodyId) {
            textView.selectedRange = NSRange(location: loc, length: 0)
            textView.typingAttributes = SpeakerSectionEditing.bodyTypingAttributes(blockId: bodyId)
            return
        }
        if let headerLoc = findSpeakerHeaderLocation(blockId: sectionId) {
            let after = headerLoc + 1
            textView.selectedRange = NSRange(location: min(after, textView.textStorage.length), length: 0)
            moveCaretOffSpeakerHeaderIfNeeded()
            textView.typingAttributes = SpeakerSectionEditing.bodyTypingAttributes(blockId: bodyId)
            return
        }
        textView.typingAttributes = SpeakerSectionEditing.bodyTypingAttributes(blockId: bodyId)
    }

    private func applyDocument(_ doc: NativeAPIClient.NoteDocument, preferBlockId: String?) {
        documentBase = doc
        applyingRemote = true
        let attributed = NoteDocumentCodec.attributedString(from: doc, speakers: speakers)
        textView.textStorage.setAttributedString(attributed)
        if let preferBlockId, let loc = findBlockLocation(blockId: preferBlockId) {
            textView.selectedRange = NSRange(location: loc, length: 0)
        } else {
            textView.selectedRange = NSRange(location: min(textView.selectedRange.location, textView.textStorage.length), length: 0)
        }
        textView.typingAttributes = typingAttributesForCaret()
        applyingRemote = false
        // Re-bake attachments under the live text-view traits (TF219 / build-234).
        refreshAttachmentAppearances()
        refreshSpeakerRails()
        emitChange()
    }

    private func findBlockLocation(blockId: String) -> Int? {
        contentLocation(forBlockId: blockId)
    }

    /// First character of `blockId` that is not a paragraph-separating newline.
    /// `appendLine` stamps the leading `\n` of a block with that block's attrs, but
    /// NSString treats that `\n` as the end of the *previous* paragraph — landing the
    /// caret there puts typing into the speaker header.
    private func contentLocation(forBlockId blockId: String) -> Int? {
        let storage = textView.textStorage
        guard storage.length > 0 else { return nil }
        let ns = storage.string as NSString
        var found: Int?
        storage.enumerateAttribute(
            NoteDocumentCodec.blockIdKey,
            in: NSRange(location: 0, length: storage.length)
        ) { value, range, stop in
            guard (value as? String) == blockId else { return }
            var loc = range.location
            while loc < ns.length,
                  ns.substring(with: NSRange(location: loc, length: 1)) == "\n",
                  loc + 1 < storage.length
            {
                let nextId = storage.attributes(at: loc + 1, effectiveRange: nil)[NoteDocumentCodec.blockIdKey] as? String
                if nextId == blockId {
                    loc += 1
                } else {
                    // Advance once into the paragraph this newline terminates into.
                    loc += 1
                    break
                }
            }
            found = min(loc, storage.length)
            stop.pointee = true
        }
        return found
    }

    private func currentBlockType() -> String {
        paragraphBlockType()
    }

    private func currentBlockId() -> String {
        let attrs = paragraphStartAttributes()
        return (attrs[NoteDocumentCodec.blockIdKey] as? String) ?? NoteDocumentCodec.newId()
    }

    private func paragraphRange() -> NSRange {
        let ns = textView.text as NSString
        let loc = min(textView.selectedRange.location, ns.length)
        return ns.paragraphRange(for: NSRange(location: loc, length: 0))
    }

    /// Apply a line block type to the current paragraph(s), including empty lines.
    private func applyBlockType(_ type: String, preserveChecked: Bool) {
        // Never restyle the non-editable speaker header — bounce into body, then apply
        // (TF200 #1: list toolbar taps while caret still on chrome must still promote).
        if currentBlockType() == "speakerSection", type != "speakerSection" {
            guard moveCaretIntoSpeakerBodyAfterHeader() else { return }
        }

        var range = paragraphRange()
        let storage = textView.textStorage
        // Snapshot before strip/insert — marker runs must not lose section membership.
        let wasSpeakerBody = NoteDocumentCodec.isSpeakerBody(paragraphStartAttributes())
        let inSection = caretIsInsideSpeakerSection() || wasSpeakerBody

        // Empty paragraph at EOF: ensure there is a character run we can attribute.
        if range.length == 0 {
            let placeholder = NSAttributedString(string: "\u{200B}", attributes: baseTypingAttributes())
            storage.replaceCharacters(in: range, with: placeholder)
            range = NSRange(location: range.location, length: 1)
            textView.selectedRange = NSRange(location: range.location + 1, length: 0)
        }

        guard storage.length >= range.location + range.length else { return }

        let checked: Bool?
        if type == "check" {
            if preserveChecked, range.length > 0 {
                let attrs = storage.attributes(at: range.location, effectiveRange: nil)
                checked = (attrs[NoteDocumentCodec.checkedKey] as? Bool) ?? false
            } else {
                checked = false
            }
        } else {
            checked = nil
        }

        let id = NoteDocumentCodec.newId()
        // Lists inside a section keep hanging indent relative to the rail (same as
        // insertContinuingListParagraph) — equal inset alone made bullets look broken.
        let isList = type == "bullet" || type == "numbered" || type == "check"
        let listNumber = numberedIndex(
            forParagraphStartingAt: range.location,
            promotingToNumbered: type == "numbered"
        )
        var styled: [NSAttributedString.Key: Any]
        if isList {
            styled = SpeakerSectionEditing.listTypingAttributes(
                type: type,
                blockId: id,
                inSpeakerSection: inSection,
                listNumber: max(listNumber, 1)
            )
            if type == "check" {
                styled[NoteDocumentCodec.checkedKey] = checked ?? false
            }
        } else {
            styled = NoteDocumentCodec.baseAttributesPublic(
                type: type,
                id: id,
                checked: checked,
                speakerId: nil,
                speakers: [:]
            )
            if inSection {
                styled = NoteDocumentCodec.applyingSpeakerSectionInset(styled)
            }
        }

        // Strip any existing display-only list marker at the start of the paragraph.
        range = stripListMarker(in: range)

        // Demoting a marker-only row can leave length 0 — reseed so attrs stick.
        if range.length == 0 {
            let placeholder = NSAttributedString(string: "\u{200B}", attributes: styled)
            storage.replaceCharacters(in: range, with: placeholder)
            range = NSRange(location: range.location, length: 1)
            textView.selectedRange = NSRange(location: range.location + 1, length: 0)
        }

        if let marker = NoteDocumentCodec.listMarkerString(type: type, checked: checked, number: listNumber) {
            var markerAttrs = styled
            markerAttrs[NoteDocumentCodec.listMarkerKey] = true
            markerAttrs[.foregroundColor] = UIColor.secondaryLabel
            let markerAttr = NSAttributedString(string: marker, attributes: markerAttrs)
            let insertAt = range.location
            let markerLen = markerAttr.length
            // Snapshot selection before the insert — mutating textStorage directly does
            // not shift UITextView.selectedRange (unlike replaceCharacters via the view).
            var sel = textView.selectedRange
            storage.insert(markerAttr, at: insertAt)
            if sel.location >= insertAt {
                sel.location += markerLen
            }
            range = NSRange(location: range.location, length: range.length + markerLen)
            // Empty / caret-in-marker → park after the marker; otherwise keep shifted end.
            if sel.length == 0, sel.location < insertAt + markerLen {
                sel = NSRange(location: insertAt + markerLen, length: 0)
            }
            textView.selectedRange = sel
        }

        storage.enumerateAttributes(in: range, options: []) { attrs, sub, _ in
            if attrs[NoteDocumentCodec.listMarkerKey] as? Bool == true {
                var markerOnly = attrs
                for (key, value) in styled where key != .foregroundColor {
                    if key == .font { continue }
                    markerOnly[key] = value
                }
                markerOnly[NoteDocumentCodec.listMarkerKey] = true
                markerOnly[NoteDocumentCodec.blockTypeKey] = type
                markerOnly[NoteDocumentCodec.blockIdKey] = id
                storage.setAttributes(markerOnly, range: sub)
                return
            }
            var next = attrs
            for (key, value) in styled {
                if key == .font, attrs[.attachment] != nil { continue }
                if key == .foregroundColor, attrs[.attachment] != nil { continue }
                next[key] = value
            }
            if type != "check" {
                next.removeValue(forKey: NoteDocumentCodec.checkedKey)
            }
            storage.setAttributes(next, range: sub)
        }

        if let para = styled[.paragraphStyle] {
            storage.addAttribute(.paragraphStyle, value: para, range: range)
        }
        storage.addAttribute(NoteDocumentCodec.blockTypeKey, value: type, range: range)
        storage.addAttribute(NoteDocumentCodec.blockIdKey, value: id, range: range)
        // Never strip an existing speakerBodyKey on promote/demote — losing it ejects the
        // line from the section in document() (TF200 lists-inside).
        let keepBody = inSection || wasSpeakerBody
            || (styled[NoteDocumentCodec.speakerBodyKey] as? Bool) == true
        if keepBody {
            storage.addAttribute(NoteDocumentCodec.speakerBodyKey, value: true, range: range)
        }
        if let checked {
            storage.addAttribute(NoteDocumentCodec.checkedKey, value: checked, range: range)
        } else {
            storage.removeAttribute(NoteDocumentCodec.checkedKey, range: range)
        }
        storage.removeAttribute(.backgroundColor, range: range)

        var typing = styled
        typing[NoteDocumentCodec.blockTypeKey] = type
        typing[NoteDocumentCodec.blockIdKey] = id
        if keepBody { typing[NoteDocumentCodec.speakerBodyKey] = true }
        if let checked { typing[NoteDocumentCodec.checkedKey] = checked }
        textView.typingAttributes = typing
        emitChange()
        refreshSpeakerRails()
    }

    private func stripListMarker(in range: NSRange) -> NSRange {
        let storage = textView.textStorage
        guard range.length > 0 else { return range }
        var markerLen = 0
        storage.enumerateAttribute(NoteDocumentCodec.listMarkerKey, in: range, options: []) { value, sub, stop in
            if value as? Bool == true, sub.location == range.location {
                markerLen = sub.length
                stop.pointee = true
            } else {
                stop.pointee = true
            }
        }
        if markerLen > 0 {
            // Direct textStorage deletes do not shift UITextView.selectedRange — without
            // this adjust, demoting an empty list item leaves the caret in the *next*
            // paragraph (often the trailing outside line), ejecting the user from the
            // speaker section (TF200 #1).
            var sel = textView.selectedRange
            storage.deleteCharacters(in: NSRange(location: range.location, length: markerLen))
            if sel.location > range.location {
                sel.location = max(range.location, sel.location - markerLen)
            }
            textView.selectedRange = sel
            return NSRange(location: range.location, length: max(0, range.length - markerLen))
        }
        return range
    }

    private func numberedIndex(forParagraphStartingAt location: Int, promotingToNumbered: Bool) -> Int {
        guard promotingToNumbered else { return 1 }
        let ns = textView.text as NSString
        var idx = 1
        var cursor = location
        while cursor > 0 {
            let prevRange = ns.paragraphRange(for: NSRange(location: cursor - 1, length: 0))
            if prevRange.length == 0 || prevRange.location >= cursor { break }
            let attrs = textView.textStorage.attributes(at: prevRange.location, effectiveRange: nil)
            if (attrs[NoteDocumentCodec.blockTypeKey] as? String) == "numbered" {
                idx += 1
                cursor = prevRange.location
            } else {
                break
            }
        }
        return idx
    }

    private func toggleMark(_ apply: (inout [NSAttributedString.Key: Any], UIFont) -> Void) {
        let range = textView.selectedRange
        if range.length == 0 {
            var typing = textView.typingAttributes
            let font = (typing[.font] as? UIFont) ?? UIFont.preferredFont(forTextStyle: .body)
            apply(&typing, font)
            textView.typingAttributes = typing
            return
        }
        textView.textStorage.enumerateAttributes(in: range, options: []) { attrs, sub, _ in
            var next = attrs
            let font = (attrs[.font] as? UIFont) ?? UIFont.preferredFont(forTextStyle: .body)
            apply(&next, font)
            textView.textStorage.setAttributes(next, range: sub)
        }
        emitChange()
    }

    @objc private func toggleHeading() {
        applyBlockType(currentBlockType() == "heading" ? "paragraph" : "heading", preserveChecked: false)
    }

    @objc private func toggleBullet() {
        applyBlockType(currentBlockType() == "bullet" ? "paragraph" : "bullet", preserveChecked: false)
    }

    @objc private func toggleNumbered() {
        applyBlockType(currentBlockType() == "numbered" ? "paragraph" : "numbered", preserveChecked: false)
    }

    @objc private func toggleCheck() {
        if currentBlockType() == "check" {
            // Flip checked state and refresh the ☐/☑ marker.
            let range = paragraphRange()
            if range.length > 0 {
                let attrs = textView.textStorage.attributes(at: range.location, effectiveRange: nil)
                let checked = !((attrs[NoteDocumentCodec.checkedKey] as? Bool) ?? false)
                textView.textStorage.addAttribute(NoteDocumentCodec.checkedKey, value: checked, range: range)
                applyBlockType("check", preserveChecked: true)
                return
            }
        }
        applyBlockType("check", preserveChecked: false)
    }

    @objc private func toggleQuote() {
        applyBlockType(currentBlockType() == "quote" ? "paragraph" : "quote", preserveChecked: false)
    }

    @objc private func toggleBoldMark() {
        toggleMark { attrs, font in
            var traits = font.fontDescriptor.symbolicTraits
            if traits.contains(.traitBold) { traits.remove(.traitBold) } else { traits.insert(.traitBold) }
            if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
                attrs[.font] = UIFont(descriptor: descriptor, size: font.pointSize)
            }
        }
    }

    @objc private func toggleItalicMark() {
        toggleMark { attrs, font in
            var traits = font.fontDescriptor.symbolicTraits
            if traits.contains(.traitItalic) { traits.remove(.traitItalic) } else { traits.insert(.traitItalic) }
            if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
                attrs[.font] = UIFont(descriptor: descriptor, size: font.pointSize)
            }
        }
    }

    @objc private func toggleUnderlineMark() {
        toggleMark { attrs, _ in
            let current = attrs[.underlineStyle] as? Int ?? 0
            if current == 0 {
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            } else {
                attrs[.underlineStyle] = 0
            }
        }
    }

    @objc private func toggleStrikeMark() {
        toggleMark { attrs, _ in
            let current = attrs[.strikethroughStyle] as? Int ?? 0
            if current == 0 {
                attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            } else {
                attrs[.strikethroughStyle] = 0
            }
        }
    }

    @objc private func presentBibleRefPicker() {
        delegate?.nativeNoteEditorRequestInsertBibleRef(self)
    }

    @objc private func presentSpeakerPicker() {
        delegate?.nativeNoteEditorRequestSpeaker(self)
    }

    // MARK: - Hit testing (bible pills vs speaker / text)

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let point = gesture.location(in: textView)
        let savedSelection = textView.selectedRange
        let wasEditing = textView.isFirstResponder

        if let ref = bibleRef(at: point) {
            // Opening a bible app must not move the caret or begin editing.
            textView.selectedRange = savedSelection
            if !wasEditing {
                textView.resignFirstResponder()
            }
            delegate?.nativeNoteEditor(self, openBibleRef: ref)
            return
        }

        if let index = characterIndex(at: point, requireHitBounds: false),
           index < textView.textStorage.length
        {
            let attrs = textView.textStorage.attributes(at: index, effectiveRange: nil)
            if let header = NoteDocumentCodec.speakerHeaderAttachment(in: attrs) {
                textView.selectedRange = savedSelection
                let hit = speakerHeaderHit(attachment: header, characterIndex: index, point: point)
                switch hit {
                case .remove:
                    confirmRemoveSpeakerSection(blockId: header.blockId)
                case .toggleCollapse:
                    toggleSpeakerCollapsed(blockId: header.blockId)
                case .rename:
                    delegate?.nativeNoteEditorRequestRenameSpeaker(
                        self,
                        sectionId: header.blockId,
                        currentSpeakerId: header.speakerId
                    )
                }
                return
            }
            // Checklist toggle when tapping the line (not a pill).
            if let type = attrs[NoteDocumentCodec.blockTypeKey] as? String, type == "check" {
                let range = (textView.text as NSString).paragraphRange(for: NSRange(location: index, length: 0))
                let checked = !((attrs[NoteDocumentCodec.checkedKey] as? Bool) ?? false)
                textView.textStorage.addAttribute(NoteDocumentCodec.checkedKey, value: checked, range: range)
                emitChange()
            }
        }
    }

    private func speakerHeaderHit(
        attachment: SpeakerHeaderAttachment,
        characterIndex index: Int,
        point: CGPoint
    ) -> SpeakerHeaderAttachment.Hit {
        let glyphIndex = textView.layoutManager.glyphIndexForCharacter(at: index)
        var rect = textView.layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyphIndex, length: 1),
            in: textView.textContainer
        )
        rect.origin.x += textView.textContainerInset.left
        rect.origin.y += textView.textContainerInset.top
        let local = CGPoint(x: point.x - rect.minX, y: point.y - rect.minY)
        return attachment.hit(at: local)
    }

    private func isSpecialTapTarget(at point: CGPoint) -> Bool {
        if bibleRef(at: point) != nil { return true }
        guard let index = characterIndex(at: point, requireHitBounds: false),
              index < textView.textStorage.length
        else { return false }
        let attrs = textView.textStorage.attributes(at: index, effectiveRange: nil)
        if NoteDocumentCodec.speakerHeaderAttachment(in: attrs) != nil { return true }
        let type = attrs[NoteDocumentCodec.blockTypeKey] as? String
        return type == "speakerSection" || type == "check"
    }

    private func toggleSpeakerCollapsed(blockId: String) {
        var doc = currentDocument()
        guard let matchIdx = doc.body.blocks.firstIndex(where: { $0.id == blockId && $0.type == "speakerSection" })
        else { return }
        var block = doc.body.blocks[matchIdx]
        let nextCollapsed = !(block.collapsed == true)
        block.collapsed = nextCollapsed ? true : nil
        doc.body.blocks[matchIdx] = block
        applyDocument(doc, preferBlockId: blockId)
        // Prefer caret in first body when expanding; stay off the attachment when collapsed.
        if nextCollapsed == false, let bodyId = block.blocks?.first?.id {
            placeCaretInSpeakerBody(bodyId: bodyId, sectionId: blockId)
        } else if let headerLoc = findSpeakerHeaderLocation(blockId: blockId) {
            textView.selectedRange = NSRange(location: min(headerLoc + 1, textView.textStorage.length), length: 0)
            moveCaretOffSpeakerHeaderIfNeeded()
        }
        KCHaptics.selection()
        UIView.animate(withDuration: 0.22) {
            self.textView.layoutIfNeeded()
        }
    }

    /// TF194: ask before × delete (product override vs web's immediate remove).
    private func confirmRemoveSpeakerSection(blockId: String) {
        let alert = UIAlertController(
            title: String(localized: "Remover seção do speaker?"),
            message: String(localized: "O texto dentro da seção também será apagado."),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "Cancelar"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "Remover seção"), style: .destructive) { [weak self] _ in
            self?.removeSpeakerSection(blockId: blockId)
        })
        guard let host = nearestViewController() else {
            removeSpeakerSection(blockId: blockId)
            return
        }
        host.present(alert, animated: true)
    }

    private func nearestViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let vc = current as? UIViewController { return vc }
            responder = current.next
        }
        return nil
    }

    private func removeSpeakerSection(blockId: String) {
        // Web `removeSpeaker`: discard the section and all body children.
        var doc = currentDocument()
        guard let idx = doc.body.blocks.firstIndex(where: { $0.id == blockId && $0.type == "speakerSection" })
        else { return }
        let focusId: String? = {
            if idx > 0 { return doc.body.blocks[idx - 1].id }
            if idx + 1 < doc.body.blocks.count { return doc.body.blocks[idx + 1].id }
            return nil
        }()
        doc.body.blocks.remove(at: idx)
        if doc.body.blocks.isEmpty {
            doc.body.blocks = [
                NativeAPIClient.LineBlock(
                    id: NoteDocumentCodec.newId(),
                    type: "paragraph",
                    spans: [],
                    speakerId: nil,
                    title: nil,
                    collapsed: nil,
                    checked: nil,
                    blocks: nil
                ),
            ]
        }
        applyDocument(doc, preferBlockId: focusId ?? doc.body.blocks.first?.id)
        KCHaptics.selection()
    }

    private func findSpeakerHeaderLocation(blockId: String) -> Int? {
        let storage = textView.textStorage
        var found: Int?
        storage.enumerateAttribute(NoteDocumentCodec.blockIdKey, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
            guard (value as? String) == blockId else { return }
            let attrs = storage.attributes(at: range.location, effectiveRange: nil)
            if (attrs[NoteDocumentCodec.blockTypeKey] as? String) == "speakerSection" {
                found = range.location
                stop.pointee = true
            }
        }
        return found
    }

    private func textPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x - textView.textContainerInset.left,
            y: point.y - textView.textContainerInset.top
        )
    }

    private func characterIndex(at point: CGPoint, requireHitBounds: Bool) -> Int? {
        let p = textPoint(point)
        var fraction: CGFloat = 0
        let index = textView.layoutManager.characterIndex(
            for: p,
            in: textView.textContainer,
            fractionOfDistanceBetweenInsertionPoints: &fraction
        )
        guard index < textView.textStorage.length else { return nil }
        if requireHitBounds {
            let glyphIndex = textView.layoutManager.glyphIndexForCharacter(at: index)
            var rect = textView.layoutManager.boundingRect(
                forGlyphRange: NSRange(location: glyphIndex, length: 1),
                in: textView.textContainer
            )
            rect.origin.x += textView.textContainerInset.left
            rect.origin.y += textView.textContainerInset.top
            guard rect.insetBy(dx: -6, dy: -6).contains(point) else { return nil }
        }
        return index
    }

    private func glyphRect(forCharacter index: Int) -> CGRect {
        let glyphIndex = textView.layoutManager.glyphIndexForCharacter(at: index)
        var rect = textView.layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyphIndex, length: 1),
            in: textView.textContainer
        )
        rect.origin.x += textView.textContainerInset.left
        rect.origin.y += textView.textContainerInset.top
        return rect
    }

    private func bibleRef(at point: CGPoint) -> NoteDocumentCodec.BibleRefPayload? {
        let storage = textView.textStorage
        guard storage.length > 0 else { return nil }
        let p = textPoint(point)
        var fraction: CGFloat = 0
        let rawIndex = textView.layoutManager.characterIndex(
            for: p,
            in: textView.textContainer,
            fractionOfDistanceBetweenInsertionPoints: &fraction
        )
        // Search the hit character and immediate neighbors (ZWSP pads around pills).
        var candidates = Set<Int>()
        for offset in -2...2 {
            let i = rawIndex + offset
            if i >= 0, i < storage.length { candidates.insert(i) }
        }
        for i in candidates.sorted() {
            let attrs = storage.attributes(at: i, effectiveRange: nil)
            // Speaker headers are plain text now — never treat them as bible pills.
            if (attrs[NoteDocumentCodec.blockTypeKey] as? String) == "speakerSection" { continue }
            if let attachment = attrs[.attachment] as? BibleRefPillAttachment {
                let rect = glyphRect(forCharacter: i).insetBy(dx: -8, dy: -8)
                if rect.contains(point) {
                    return attachment.payload
                }
            }
            if let payload = attrs[NoteDocumentCodec.bibleRefKey] as? NoteDocumentCodec.BibleRefPayload {
                let rect = glyphRect(forCharacter: i).insetBy(dx: -8, dy: -8)
                if rect.contains(point) {
                    return payload
                }
            }
        }
        return nil
    }

    // MARK: - Placeholders (title + body)

    private func refreshPlaceholders() {
        let doc = currentDocument()
        let titleEmpty = doc.title
            .replacingOccurrences(of: "\u{200B}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        titlePlaceholderLabel.isHidden = !titleEmpty
        // Hide body placeholder whenever the body has any content — plain text,
        // bibleRef pills, speaker headers, or any other attachment (TF210).
        bodyPlaceholderLabel.isHidden = bodyHasVisibleContent()
        repositionTagsStrip()
    }

    /// True when the body region of `textStorage` is non-empty (attachments count).
    private func bodyHasVisibleContent() -> Bool {
        let storage = textView.textStorage
        guard storage.length > 0 else { return false }
        let titlePara = (storage.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
        let bodyStart = NSMaxRange(titlePara)
        guard bodyStart < storage.length else { return false }
        let bodyRange = NSRange(location: bodyStart, length: storage.length - bodyStart)
        var found = false
        storage.enumerateAttributes(in: bodyRange, options: []) { attrs, range, stop in
            if attrs[.attachment] != nil {
                found = true
                stop.pointee = true
                return
            }
            if attrs[NoteDocumentCodec.bibleRefKey] != nil {
                found = true
                stop.pointee = true
                return
            }
            let chunk = (storage.string as NSString).substring(with: range)
                .replacingOccurrences(of: "\u{200B}", with: "")
                .replacingOccurrences(of: "\n", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunk.isEmpty {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    // MARK: - AppTests seams (real UITextView path)

    /// Prepare a frameless editor for AppTests. Avoid creating a second key `UIWindow` —
    /// AppTests run inside the app host and fighting SceneDelegate's window flakes/hangs CI.
    func testing_prepare(size: CGSize = CGSize(width: 390, height: 844)) {
        frame = CGRect(origin: .zero, size: size)
        textView.frame = bounds
        // Width tracks the view; height must stay unbounded so long notes actually lay out
        // (a finite height clips TextKit and breaks caret/contentOffset math).
        textView.textContainer.size = CGSize(
            width: max(0, size.width - textView.textContainerInset.left - textView.textContainerInset.right - 5),
            height: .greatestFiniteMagnitude
        )
        textView.textContainer.heightTracksTextView = false
        textView.layoutManager.ensureLayout(for: textView.textContainer)
        layoutIfNeeded()
    }

    /// Simulate a keyboard insertion the way UIKit does: ask `shouldChangeTextIn`, then
    /// either let our handler mutate storage (Return → false) or apply typingAttributes (true).
    /// Replaces a trailing ZWSP placeholder (empty-body anchor) the way typing usually does.
    func testing_insertText(_ string: String) {
        // Leave non-editable header chrome before any ordinary character.
        if paragraphBlockType() == "speakerSection", !Self.isNewlineReplacement(string) {
            _ = moveCaretIntoSpeakerBodyAfterHeader()
        }

        func applyOrdinaryInsertion(at range: inout NSRange) {
            if range.length == 0,
               !Self.isNewlineReplacement(string),
               range.location <= textView.textStorage.length
            {
                let ns = textView.textStorage.string as NSString
                if range.location < ns.length,
                   ns.substring(with: NSRange(location: range.location, length: 1)) == "\u{200B}"
                {
                    range = NSRange(location: range.location, length: 1)
                } else if range.location > 0,
                          ns.substring(with: NSRange(location: range.location - 1, length: 1)) == "\u{200B}"
                {
                    range = NSRange(location: range.location - 1, length: 1)
                }
            }
            let attrs = textView.typingAttributes
            let piece = NSAttributedString(string: string, attributes: attrs)
            textView.textStorage.replaceCharacters(in: range, with: piece)
            textView.selectedRange = NSRange(location: range.location + piece.length, length: 0)
            textViewDidChange(textView)
        }

        var range = textView.selectedRange
        let allowed = textView(textView, shouldChangeTextIn: range, replacementText: string)
        if allowed {
            applyOrdinaryInsertion(at: &range)
            return
        }

        // `shouldChangeTextIn` returned false:
        // - Enter inside speaker → already inserted/exited in the delegate
        // - Enter/typing on header → caret was bounced into body; retry once
        if Self.isNewlineReplacement(string) {
            if paragraphBlockType() == "speakerSection" { return }
            // Delegate already handled continue/exit when inside a speaker body.
            return
        }
        if paragraphBlockType() == "speakerSection" { return }
        range = textView.selectedRange
        let retry = textView(textView, shouldChangeTextIn: range, replacementText: string)
        guard retry else { return }
        applyOrdinaryInsertion(at: &range)
    }

    func testing_selectedRange() -> NSRange {
        textView.selectedRange
    }

    func testing_setSelectedRange(_ range: NSRange) {
        let length = textView.textStorage.length
        let loc = min(max(0, range.location), length)
        let len = min(max(0, range.length), max(0, length - loc))
        textView.selectedRange = NSRange(location: loc, length: len)
        // Always re-seed from the caret paragraph — title typing attrs must not
        // leak into the body after a selection move (TF194 list promote/Enter).
        textView.typingAttributes = typingAttributesForCaret()
    }

    func testing_textStorage() -> NSTextStorage {
        textView.textStorage
    }

    func testing_railCharacterRanges() -> [NSRange] {
        railLayoutManager.rails.map(\.range)
    }

    func testing_paragraphBlockType() -> String {
        paragraphBlockType()
    }

    func testing_toggleCollapse(sectionId: String) {
        toggleSpeakerCollapsed(blockId: sectionId)
    }

    func testing_removeSection(sectionId: String) {
        removeSpeakerSection(blockId: sectionId)
    }

    func testing_applyBlockTypeHook(_ type: String) {
        applyBlockType(type, preserveChecked: false)
    }

    func testing_headerAttachment(at location: Int) -> SpeakerHeaderAttachment? {
        guard textView.textStorage.length > 0 else { return nil }
        let loc = min(max(0, location), textView.textStorage.length - 1)
        return NoteDocumentCodec.speakerHeaderAttachment(
            in: textView.textStorage.attributes(at: loc, effectiveRange: nil)
        )
    }

    func testing_titlePlaceholderVisible() -> Bool {
        refreshPlaceholders()
        return !titlePlaceholderLabel.isHidden
    }

    func testing_bodyPlaceholderVisible() -> Bool {
        refreshPlaceholders()
        return !bodyPlaceholderLabel.isHidden
    }

    func testing_titlePlaceholderText() -> String? {
        titlePlaceholderLabel.text
    }

    func testing_bodyPlaceholderText() -> String? {
        bodyPlaceholderLabel.text
    }

    func testing_setTags(_ tags: [String]) {
        tagsStrip.setTags(tags)
        applyTags(tags)
    }

    func testing_tags() -> [String] {
        tagsStrip.currentTags()
    }

    func testing_isFormattingToolbarVisible() -> Bool {
        textView.inputAccessoryView != nil
    }

    func testing_refreshSpeakerHeaderAppearances() {
        refreshSpeakerHeaderAppearances(force: true)
    }

    func testing_refreshBibleRefPillAppearances() {
        refreshBibleRefPillAppearances(force: true)
    }

    func testing_refreshAttachmentAppearances() {
        forceRefreshAttachmentAppearances()
    }

    func testing_refreshAppearanceForCurrentTraits() {
        refreshAppearanceForCurrentTraits(forceAttachments: true)
    }

    /// Resolved title (first paragraph) foreground under the given traits — AppTests.
    func testing_titleForegroundColor(traits: UITraitCollection) -> UIColor? {
        let storage = textView.textStorage
        guard storage.length > 0 else { return nil }
        let para = (storage.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
        guard para.length > 0 else { return nil }
        var sampleLoc = para.location
        let ns = storage.string as NSString
        while sampleLoc < NSMaxRange(para) {
            let ch = ns.substring(with: NSRange(location: sampleLoc, length: 1))
            if ch == "\u{200B}" || ch == "\n" {
                sampleLoc += 1
                continue
            }
            break
        }
        let loc = min(sampleLoc, max(0, storage.length - 1))
        guard let fg = storage.attribute(.foregroundColor, at: loc, effectiveRange: nil) as? UIColor else {
            return nil
        }
        return fg.resolvedColor(with: traits)
    }

    func testing_contentOffset() -> CGPoint {
        textView.contentOffset
    }

    func testing_setContentOffset(_ offset: CGPoint) {
        textView.setContentOffset(offset, animated: false)
    }

    func testing_contentSize() -> CGSize {
        textView.layoutManager.ensureLayout(for: textView.textContainer)
        textView.layoutIfNeeded()
        return textView.contentSize
    }

    func testing_boundsHeight() -> CGFloat {
        textView.bounds.height
    }

    func testing_contentInset() -> UIEdgeInsets {
        textView.contentInset
    }

    /// Simulate keyboard + accessory bottom inset without posting notifications.
    func testing_setKeyboardBottomInset(_ bottom: CGFloat) {
        keyboardOverlap = max(0, bottom)
        let accessoryPad: CGFloat = bottom > 0 ? KCDesign.Space.md : 0
        textView.contentInset.bottom = bottom + accessoryPad
        textView.verticalScrollIndicatorInsets.bottom = bottom + accessoryPad
        textView.textContainerInset.bottom = baseBottomInset + (bottom > 0 ? KCDesign.Space.sm : 0)
        textView.layoutIfNeeded()
    }

    func testing_scrollCaretVisible(animated: Bool = false) {
        let previous = testing_forceCaretScroll
        testing_forceCaretScroll = true
        defer { testing_forceCaretScroll = previous }
        scrollCaretVisible(animated: animated)
    }

    func testing_caretRectInBounds() -> CGRect {
        caretRectInBoundsForScroll() ?? .null
    }

    func testing_measuredContentHeight() -> CGFloat {
        measuredContentHeight()
    }

    /// Delete backward one character/selection the way the keyboard does (Backspace).
    func testing_deleteBackward() {
        var range = textView.selectedRange
        if range.length == 0 {
            guard range.location > 0 else { return }
            range = NSRange(location: range.location - 1, length: 1)
        }
        let allowed = textView(textView, shouldChangeTextIn: range, replacementText: "")
        guard allowed else { return }
        textView.textStorage.replaceCharacters(in: range, with: "")
        textView.selectedRange = NSRange(location: range.location, length: 0)
        textView.typingAttributes = typingAttributesForCaret()
        textViewDidChange(textView)
    }

    @discardableResult
    func testing_becomeFirstResponder() -> Bool {
        textView.becomeFirstResponder()
    }
}

extension NativeNoteEditorView: UIGestureRecognizerDelegate {
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // Only steal taps that hit bible pills / speaker headers / checkboxes —
        // so a bible-ref tap never moves the caret into the next line.
        // UIView already defines this method, so we must override it (not only
        // satisfy the delegate protocol).
        guard gestureRecognizer === tapGesture else {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
        let point = gestureRecognizer.location(in: textView)
        return isSpecialTapTarget(at: point)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }
}

// MARK: - Codec helpers exposed for typing attributes

extension NoteDocumentCodec {
    /// Alias kept for call sites — always the same dictionary as the load path.
    static func baseAttributesPublic(
        type: String,
        id: String,
        checked: Bool?,
        speakerId: String?,
        speakers: [String: NativeAPIClient.SpeakerDTO]
    ) -> [NSAttributedString.Key: Any] {
        baseAttributes(type: type, id: id, checked: checked, speakerId: speakerId, speakers: speakers)
    }
}

// MARK: - Caret scroll (unit-tested)

/// Minimal contentOffset math so Enter/Backspace never pin the caret line to the
/// top of the viewport (the `UITextView.scrollRangeToVisible` + keyboard inset bug).
///
/// Contract:
/// - caret already in the inset-adjusted band → keep `currentOffsetY` (then clamp)
/// - caret below the band → increase offset by exactly the overflow (≈ one line on Enter)
/// - caret above the band → decrease offset by exactly the overflow
/// - never jump to pin the caret line to the top of the viewport
enum NoteEditorCaretScroll {
    /// `caretRectInBounds` is UITextView's caret rect (view coordinates, not content).
    static func contentOffsetY(
        caretRectInBounds: CGRect,
        boundsHeight: CGFloat,
        contentInset: UIEdgeInsets,
        contentSizeHeight: CGFloat,
        currentOffsetY: CGFloat,
        padding: CGFloat = 4
    ) -> CGFloat {
        let minOffset = -contentInset.top
        let maxOffset = max(minOffset, contentSizeHeight - boundsHeight + contentInset.bottom)

        // Visible band inside the text view frame, above the keyboard/accessory inset.
        let visibleTop = contentInset.top + padding
        let visibleBottom = boundsHeight - contentInset.bottom - padding

        var target = currentOffsetY
        let caretTop = caretRectInBounds.minY
        let caretBottom = caretRectInBounds.maxY

        if caretBottom > visibleBottom {
            // Caret below the usable area — scroll down just enough.
            target = currentOffsetY + (caretBottom - visibleBottom)
        } else if caretTop < visibleTop {
            // Caret above the usable area — scroll up just enough.
            target = currentOffsetY + (caretTop - visibleTop)
        }
        // else: already visible — preserve contentOffset (then clamp for shrinks).

        return min(max(target, minOffset), maxOffset)
    }
}

// MARK: - Speaker Enter decision (unit-tested)

/// Pure decision for Enter inside/near speaker sections — keeps UIKit out of XCTest.
enum SpeakerEnterDecision: Equatable {
    case insertBodyFromHeader
    /// New paragraph that must stay inside the speaker (manual insert with speakerBodyKey).
    case continueInSection
    case demoteListToParagraph
    case exitSection
    case continueList(String)
    case defaultNewline

    static func decide(
        blockType: String,
        insideSpeaker: Bool,
        paragraphEmpty: Bool,
        isLastBodyOfSection: Bool
    ) -> SpeakerEnterDecision {
        if blockType == "speakerSection" {
            return .insertBodyFromHeader
        }
        if blockType == "bullet" || blockType == "numbered" || blockType == "check" || blockType == "quote" {
            // Web onEnter: empty ul/ol/quote → demote; else continue kind (inside or outside).
            if paragraphEmpty {
                return .demoteListToParagraph
            }
            return .continueList(blockType)
        }
        if insideSpeaker {
            if paragraphEmpty, isLastBodyOfSection {
                return .exitSection
            }
            // Non-empty body Enter, or empty non-last body → stay inside with a real body run.
            return .continueInSection
        }
        return .defaultNewline
    }
}

// MARK: - Text view (caret height = font line height)

/// Clamps the caret to the font line height so `paragraphSpacing` does not stretch the cursor.
final class NoteEditorTextView: UITextView {
    /// Invoked instead of UIKit's pin-to-top `scrollRangeToVisible` (keyboard inset bug).
    /// Must run the editor's minimal caret-scroll helper so Enter/typing still follow the caret.
    var onRequestCaretScroll: (() -> Void)?

    /// When set, UIKit/TextKit cannot rewrite `contentOffset` (prevents mid-edit clamp-to-0).
    var stickyContentOffset: CGPoint?

    /// Re-entrancy guard: `onRequestCaretScroll` → `setContentOffset` must not loop.
    private var isHandlingCaretScrollRequest = false

    override func caretRect(for position: UITextPosition) -> CGRect {
        var rect = super.caretRect(for: position)
        let font = caretFont(at: position)
        let lineHeight = ceil(font.lineHeight)
        if rect.height > lineHeight + 0.5 {
            rect.size.height = lineHeight
        }
        return rect
    }

    override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        if let sticky = stickyContentOffset {
            super.setContentOffset(sticky, animated: false)
            return
        }
        super.setContentOffset(contentOffset, animated: animated)
    }

    /// UIKit's default, with a large keyboard `contentInset.bottom`, pins the caret line
    /// to the top of the viewport. Forward to `NativeNoteEditorView`'s minimal scroll
    /// (restore pre-edit offset + scroll only if the caret left the visible band).
    override func scrollRangeToVisible(_ range: NSRange) {
        guard !isHandlingCaretScrollRequest else { return }
        isHandlingCaretScrollRequest = true
        defer { isHandlingCaretScrollRequest = false }
        if let onRequestCaretScroll {
            onRequestCaretScroll()
        }
        // If the host has not wired a handler yet, do nothing (never call super).
    }

    private func caretFont(at position: UITextPosition) -> UIFont {
        if let font = typingAttributes[.font] as? UIFont {
            return font
        }
        let offset = self.offset(from: beginningOfDocument, to: position)
        let storage = textStorage
        if storage.length > 0 {
            let index = min(max(offset, 0), storage.length - 1)
            if let font = storage.attribute(.font, at: index, effectiveRange: nil) as? UIFont {
                return font
            }
        }
        return .preferredFont(forTextStyle: .body)
    }
}

// MARK: - Speaker section vertical rail

/// Draws the left colored bar for speaker sections (web `.note-speaker { border-left }`).
final class NoteSpeakerRailLayoutManager: NSLayoutManager {
    var rails: [(range: NSRange, color: UIColor)] = []

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let container = textContainers.first, !rails.isEmpty else { return }
        let inset = NoteDocumentCodec.speakerSectionContentInset
        let railW = NoteDocumentCodec.speakerRailWidth
        for rail in rails {
            guard rail.range.length > 0 else { continue }
            let glyphRange = self.glyphRange(forCharacterRange: rail.range, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { continue }
            var union = CGRect.null
            enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, _, _ in
                if usedRect.height > 0 {
                    union = union.isNull ? usedRect : union.union(usedRect)
                }
            }
            if union.isNull {
                let bounds = boundingRect(forGlyphRange: glyphRange, in: container)
                guard bounds.height > 0 else { continue }
                union = bounds
            }
            // Place the rail in the section’s left inset (padding-left of the web section).
            let x = origin.x + max(0, union.minX - inset + 2)
            let bar = CGRect(
                x: x,
                y: origin.y + union.minY,
                width: railW,
                height: max(union.height, 18)
            )
            rail.color.setFill()
            UIBezierPath(roundedRect: bar, cornerRadius: 1).fill()
        }
    }
}

// MARK: - Compact keyboard accessory (scrollable + Liquid Glass)

@MainActor
final class NoteEditorAccessoryBar: UIView {
    enum Action {
        case bold, italic, underline, strike
        case heading, bullet, numbered, check, quote
        case bibleRef, speaker
    }

    var onAction: ((Action) -> Void)?

    private let blur: UIVisualEffectView
    private let scroll = UIScrollView()
    private let stack = UIStackView()

    init() {
        let effect = KCGlassMaterial.effect(withInteractive: true) ?? UIBlurEffect(style: .systemChromeMaterial)
        blur = UIVisualEffectView(effect: effect)
        super.init(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 52))
        autoresizingMask = [.flexibleWidth]
        backgroundColor = .clear

        blur.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blur)

        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = true
        scroll.contentInset = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        addSubview(scroll)

        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        // TF210: speaker + reference first, then formatting. No undo/redo buttons.
        let groups: [[(String, Action, String)]] = [
            [
                ("person.wave.2", .speaker, String(localized: "Speaker")),
                ("book", .bibleRef, String(localized: "Referência bíblica")),
            ],
            [
                ("bold", .bold, String(localized: "Negrito")),
                ("italic", .italic, String(localized: "Itálico")),
                ("underline", .underline, String(localized: "Sublinhado")),
                ("strikethrough", .strike, String(localized: "Riscado")),
            ],
            [
                ("textformat.size", .heading, String(localized: "Título")),
                ("list.bullet", .bullet, String(localized: "Lista")),
                ("list.number", .numbered, String(localized: "Numerada")),
                ("checklist", .check, String(localized: "Checklist")),
                ("text.quote", .quote, String(localized: "Citação")),
            ],
        ]

        for (groupIndex, group) in groups.enumerated() {
            if groupIndex > 0 {
                let sep = UIView()
                sep.translatesAutoresizingMaskIntoConstraints = false
                sep.backgroundColor = KCDesign.separator
                sep.widthAnchor.constraint(equalToConstant: 1).isActive = true
                sep.heightAnchor.constraint(equalToConstant: 22).isActive = true
                stack.addArrangedSubview(sep)
            }
            for (symbol, action, label) in group {
                stack.addArrangedSubview(makeButton(symbol: symbol, action: action, label: label))
            }
        }

        NSLayoutConstraint.activate([
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor),

            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])

        let hairline = UIView()
        hairline.translatesAutoresizingMaskIntoConstraints = false
        hairline.backgroundColor = KCDesign.separator
        addSubview(hairline)
        NSLayoutConstraint.activate([
            hairline.topAnchor.constraint(equalTo: topAnchor),
            hairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 0.5),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func makeButton(symbol: String, action: Action, label: String) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: symbol)
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
        config.baseForegroundColor = KCDesign.accent
        button.configuration = config
        button.accessibilityLabel = label
        button.addAction(UIAction { [weak self] _ in
            self?.onAction?(action)
        }, for: .touchUpInside)
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        return button
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 52)
    }

    /// Ordered accessibility labels of toolbar buttons (AppTests / TF210).
    static func testing_actionLabels() -> [String] {
        let bar = NoteEditorAccessoryBar()
        return bar.stack.arrangedSubviews.compactMap { view in
            (view as? UIButton)?.accessibilityLabel
        }
    }
}
