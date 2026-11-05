import UIKit

@MainActor
protocol NativeNoteEditorViewDelegate: AnyObject {
    func nativeNoteEditorDidChange(_ editor: NativeNoteEditorView, document: NativeAPIClient.NoteDocument)
    func nativeNoteEditor(_ editor: NativeNoteEditorView, openBibleRef ref: NoteDocumentCodec.BibleRefPayload)
    func nativeNoteEditorRequestInsertBibleRef(_ editor: NativeNoteEditorView)
    func nativeNoteEditorRequestSpeaker(_ editor: NativeNoteEditorView)
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
    private var baseBottomInset: CGFloat = V2NDesign.Space.lg
    private var triggerMenu: NoteEditorTriggerMenuView?
    private var triggerMenuTopConstraint: NSLayoutConstraint?
    private var triggerMenuLeadingConstraint: NSLayoutConstraint?
    private var keyboardOverlap: CGFloat = 0
    private var isBodyEditing = false
    private var tapGesture: UITapGestureRecognizer!

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
        backgroundColor = V2NDesign.canvas

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.delegate = self
        textView.backgroundColor = V2NDesign.canvas
        textView.textContainerInset = UIEdgeInsets(
            top: V2NDesign.Space.md,
            left: V2NDesign.Space.md,
            bottom: baseBottomInset,
            right: V2NDesign.Space.md
        )
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.adjustsFontForContentSizeCategory = true
        textView.allowsEditingTextAttributes = true
        textView.tintColor = V2NDesign.accent
        textView.accessibilityLabel = String(localized: "Corpo da nota")
        textView.accessibilityHint = String(localized: "A primeira linha é o título")
        addSubview(textView)

        accessory.onAction = { [weak self] action in
            self?.handleAccessory(action)
        }
        // Formatting toolbar appears only after the user taps into the body (edit mode).
        textView.inputAccessoryView = nil

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.delegate = self
        // Cancel the text view's caret move when we handle bible/speaker/check taps.
        tap.cancelsTouchesInView = true
        tapGesture = tap
        textView.addGestureRecognizer(tap)

        observeKeyboard()
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
        let bottom = overlap + (overlap > 0 ? accessoryH + V2NDesign.Space.md : 0)

        UIView.animate(withDuration: duration, delay: 0, options: options) {
            self.textView.contentInset.bottom = bottom
            self.textView.verticalScrollIndicatorInsets.bottom = bottom
            self.textView.textContainerInset.bottom = self.baseBottomInset + (overlap > 0 ? V2NDesign.Space.sm : 0)
            self.repositionTriggerMenuIfNeeded()
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

    private func scrollCaretVisible(animated: Bool) {
        guard textView.isFirstResponder else { return }
        let range = textView.selectedRange
        if animated {
            textView.scrollRangeToVisible(range)
        } else {
            UIView.performWithoutAnimation {
                textView.scrollRangeToVisible(range)
            }
        }
    }

    /// Load / replace the document currently shown.
    func pushNote(_ note: NativeAPIClient.NoteDocument, speakers: [NativeAPIClient.SpeakerDTO] = [], readOnly: Bool = false) {
        precondition(Thread.isMainThread)
        documentBase = note
        self.speakers = speakers
        applyingRemote = true
        dismissTriggerMenu()
        let attributed = NoteDocumentCodec.attributedString(from: note, speakers: speakers)
        // Prefer textStorage mutation over attributedText reassign when possible so we
        // don't thrash selection — but a full load must replace content once.
        textView.textStorage.setAttributedString(attributed)
        textView.selectedRange = NSRange(location: 0, length: 0)
        textView.typingAttributes = typingAttributesForCaret()
        textView.isEditable = !readOnly
        applyingRemote = false
        isReady = true
        refreshSpeakerRails()
    }

    func currentDocument() -> NativeAPIClient.NoteDocument {
        precondition(Thread.isMainThread)
        // Prefer textStorage — UITextView.attributedText can drop custom keys (speakerBodyKey / blockType).
        return NoteDocumentCodec.document(from: textView.textStorage, base: documentBase)
    }

    func insertBibleRef(_ ref: NoteDocumentCodec.BibleRefPayload) {
        precondition(Thread.isMainThread)
        dismissTriggerMenu()
        var base = textView.typingAttributes
        base[NoteDocumentCodec.blockTypeKey] = currentBlockType() == "speakerSection" ? "paragraph" : currentBlockType()
        base[NoteDocumentCodec.blockIdKey] = currentBlockId()
        let piece = NoteDocumentCodec.bibleRefPill(payload: ref, base: base)
        textView.textStorage.replaceCharacters(in: textView.selectedRange, with: piece)
        let end = textView.selectedRange.location + piece.length
        textView.selectedRange = NSRange(location: end, length: 0)
        textView.typingAttributes = baseTypingAttributes()
        emitChange()
        scrollCaretVisible(animated: true)
    }

    func insertSpeakerSection(speakerId: String, name: String) {
        precondition(Thread.isMainThread)
        dismissTriggerMenu()
        let id = NoteDocumentCodec.newId()
        let colorHex = speakers.first(where: { $0.id == speakerId })?.color
        let header = NoteDocumentCodec.speakerSectionHeader(
            name: name,
            speakerId: speakerId,
            colorHex: colorHex,
            blockId: id
        )
        // Header only — do NOT seed an empty body line. Seeding made the first Enter
        // look like “Enter on empty last body” and exit the section immediately.
        let chunk = NSMutableAttributedString()
        if textView.selectedRange.location > 0, textView.textStorage.length > 0 {
            let sepAttrs = header.length > 0
                ? header.attributes(at: 0, effectiveRange: nil)
                : NoteDocumentCodec.baseAttributesPublic(
                    type: "speakerSection",
                    id: id,
                    checked: nil,
                    speakerId: speakerId,
                    speakers: [:]
                )
            chunk.append(NSAttributedString(string: "\n", attributes: sepAttrs))
        }
        chunk.append(header)
        let insertAt = textView.selectedRange.location
        textView.textStorage.replaceCharacters(in: textView.selectedRange, with: chunk)
        // Caret at end of header; first Enter creates the first body line inside.
        let caret = insertAt + chunk.length
        textView.selectedRange = NSRange(location: caret, length: 0)
        textView.typingAttributes = header.length > 0
            ? header.attributes(at: header.length - 1, effectiveRange: nil)
            : typingAttributesForCaret()
        emitChange()
        refreshSpeakerRails()
        scrollCaretVisible(animated: true)
    }

    // MARK: - UITextViewDelegate

    func textViewDidBeginEditing(_ textView: UITextView) {
        setEditingChrome(true)
        ensureTypingAttributes()
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        setEditingChrome(false)
        dismissTriggerMenu()
    }

    func textViewDidChange(_ textView: UITextView) {
        guard !applyingRemote else { return }
        if textView.textStorage.length == 0 {
            reseedEmptyDocument()
            return
        }
        // CRITICAL: never demote header typingAttributes to paragraph while the caret is still
        // on the speaker name line. PR #60's pure helpers passed, but this rewrite made the next
        // typed name characters (and then Enter) look like a body/outside paragraph to UIKit.
        if paragraphBlockType() == "speakerSection" {
            normalizeSpeakerHeaderParagraphAttributes()
            textView.typingAttributes = typingAttributesForCaret()
        } else if caretIsInsideSpeakerSection() {
            normalizeSpeakerBodyParagraphAttributes()
            textView.typingAttributes = SpeakerSectionEditing.bodyTypingAttributes(
                blockId: currentBlockId()
            )
        } else {
            ensureTypingAttributes()
        }
        // Never reassign attributedText here — preserve selection, undo stack, and IME marked text.
        emitChange()
        refreshSpeakerRails()
        scrollCaretVisible(animated: false)
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        if !applyingRemote {
            ensureTypingAttributes()
        }
        if triggerMenu != nil {
            repositionTriggerMenuIfNeeded()
        }
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        // Keep attrs in sync before deciding — but resolve block type from the *paragraph start*
        // (see paragraphBlockType), not the caret character UIKit just typed with demoted attrs.
        if paragraphBlockType() == "speakerSection" {
            textView.typingAttributes = typingAttributesForCaret()
        } else if caretIsInsideSpeakerSection() {
            textView.typingAttributes = SpeakerSectionEditing.bodyTypingAttributes(
                blockId: currentBlockId()
            )
        } else {
            ensureTypingAttributes()
        }

        if Self.isNewlineReplacement(text) {
            dismissTriggerMenu()
            // Use paragraph-start type so Enter on a name line whose trailing runs were
            // corrupted to "paragraph" still inserts a body *inside* the section.
            let type = paragraphBlockType()
            let inside = caretIsInsideSpeakerSection() || type == "speakerSection"
            let decision = SpeakerEnterDecision.decide(
                blockType: type,
                insideSpeaker: inside,
                paragraphEmpty: isCurrentParagraphVisuallyEmpty(),
                isLastBodyOfSection: isLastBodyParagraphOfSpeakerSection()
            )
            switch decision {
            case .insertBodyFromHeader:
                insertSpeakerBodyParagraph()
                return false
            case .continueInSection:
                // Never let UIKit insert a bare newline — new paragraph must carry speakerBodyKey.
                insertContinuingSpeakerBodyParagraph()
                return false
            case .demoteListToParagraph:
                applyBlockType("paragraph", preserveChecked: false)
                return false
            case .exitSection:
                exitSpeakerSection()
                return false
            case .continueList(let listType):
                DispatchQueue.main.async { [weak self] in
                    self?.applyBlockType(listType, preserveChecked: true)
                }
                return true
            case .defaultNewline:
                // Belt-and-suspenders: never allow a bare UIKit newline inside a speaker section.
                if inside {
                    insertContinuingSpeakerBodyParagraph()
                    return false
                }
                return true
            }
        }

        // Typing inside an existing speaker body must keep speakerBodyKey + inset.
        // Returning true alone is not enough — UIKit may ignore typingAttributes mutated here —
        // so textViewDidChange also re-stamps the paragraph (normalizeSpeakerBodyParagraphAttributes).
        if caretIsInsideSpeakerSection(), paragraphBlockType() != "speakerSection" {
            textView.typingAttributes = SpeakerSectionEditing.bodyTypingAttributes(
                blockId: currentBlockId()
            )
        }

        if text == "@" || text == "/" {
            let beforeOK = isTriggerPrefixAllowed(before: range)
            if beforeOK {
                // Insert the character first? Original strips it. Consume without inserting and open menu.
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if text == "@" {
                        self.showAtMenu(at: range.location)
                    } else {
                        self.showSlashMenu(at: range.location)
                    }
                }
                return false
            }
        }

        if triggerMenu != nil, text.isEmpty, range.length > 0 {
            // Backspace while menu open — dismiss.
            dismissTriggerMenu()
        }

        return true
    }

    private func isTriggerPrefixAllowed(before range: NSRange) -> Bool {
        if range.location == 0 { return true }
        let ns = (textView.text as NSString)
        let prev = ns.substring(with: NSRange(location: range.location - 1, length: 1))
        return prev.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
    }

    private func emitChange() {
        let doc = currentDocument()
        documentBase = doc
        delegate?.nativeNoteEditorDidChange(self, document: doc)
    }

    // MARK: - Accessory

    private func handleAccessory(_ action: NoteEditorAccessoryBar.Action) {
        dismissTriggerMenu()
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
        case .undo: undoEdit()
        case .redo: redoEdit()
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
            // Typing on the header edits the speaker name — keep header attrs.
            var header = NoteDocumentCodec.baseAttributesPublic(
                type: "speakerSection",
                id: currentBlockId(),
                checked: nil,
                speakerId: nil,
                speakers: [:]
            )
            header = NoteDocumentCodec.applyingSpeakerSectionInset(header)
            return header
        }
        var attrs = NoteDocumentCodec.baseAttributesPublic(
            type: rawType,
            id: currentBlockId(),
            checked: rawType == "check" ? false : nil,
            speakerId: nil,
            speakers: [:]
        )
        if caretIsInsideSpeakerSection() {
            attrs = NoteDocumentCodec.applyingSpeakerSectionInset(attrs)
        }
        return attrs
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
        guard missingBlock || missingFont || missingPara else { return }
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
    }

    private func insertSpeakerBodyParagraph() {
        let header = paragraphRange()
        let result = SpeakerSectionEditing.insertBodyAfterHeader(
            in: textView.textStorage,
            headerRange: header
        )
        textView.selectedRange = NSRange(location: result.caret, length: 0)
        textView.typingAttributes = result.typingAttributes
        emitChange()
        refreshSpeakerRails()
        scrollCaretVisible(animated: true)
    }

    private func insertContinuingSpeakerBodyParagraph() {
        let result = SpeakerSectionEditing.insertContinuingBodyParagraph(
            in: textView.textStorage,
            paragraphRange: paragraphRange()
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

    /// Re-stamp speakerSection metadata on the whole name line so mid-line typing cannot split it.
    private func normalizeSpeakerHeaderParagraphAttributes() {
        let storage = textView.textStorage
        let para = paragraphRange()
        guard para.length > 0, storage.length >= NSMaxRange(para) else { return }
        let startAttrs = paragraphStartAttributes()
        guard (startAttrs[NoteDocumentCodec.blockTypeKey] as? String) == "speakerSection" else { return }
        let id = (startAttrs[NoteDocumentCodec.blockIdKey] as? String) ?? NoteDocumentCodec.newId()
        let speakerId = startAttrs[NoteDocumentCodec.speakerIdKey] as? String
        var stamped = NoteDocumentCodec.baseAttributesPublic(
            type: "speakerSection",
            id: id,
            checked: nil,
            speakerId: speakerId,
            speakers: [:]
        )
        stamped = NoteDocumentCodec.applyingSpeakerSectionInset(stamped)
        if let collapsed = startAttrs[NoteDocumentCodec.collapsedKey] {
            stamped[NoteDocumentCodec.collapsedKey] = collapsed
        }
        // Preserve per-run font/color (user formatting) but force block metadata + inset style.
        storage.enumerateAttributes(in: para, options: []) { attrs, sub, _ in
            var next = attrs
            next[NoteDocumentCodec.blockTypeKey] = "speakerSection"
            next[NoteDocumentCodec.blockIdKey] = id
            if let speakerId {
                next[NoteDocumentCodec.speakerIdKey] = speakerId
            }
            if let style = stamped[.paragraphStyle] {
                next[.paragraphStyle] = style
            }
            next[NoteDocumentCodec.speakerBodyKey] = true
            storage.setAttributes(next, range: sub)
        }
    }

    /// Re-stamp speakerBodyKey + inset on the body paragraph UIKit may have inserted bare.
    private func normalizeSpeakerBodyParagraphAttributes() {
        let storage = textView.textStorage
        let para = paragraphRange()
        guard para.length > 0, storage.length >= NSMaxRange(para) else { return }
        let id = currentBlockId()
        let body = SpeakerSectionEditing.bodyTypingAttributes(blockId: id)
        storage.enumerateAttributes(in: para, options: []) { attrs, sub, _ in
            if (attrs[NoteDocumentCodec.blockTypeKey] as? String) == "speakerSection" { return }
            var next = attrs
            next[NoteDocumentCodec.blockTypeKey] = "paragraph"
            next[NoteDocumentCodec.blockIdKey] = id
            next[NoteDocumentCodec.speakerBodyKey] = true
            if let style = body[.paragraphStyle] {
                next[.paragraphStyle] = style
            }
            storage.setAttributes(next, range: sub)
        }
    }

    private func enclosingSpeakerSectionStart() -> Int? {
        guard caretIsInsideSpeakerSection() else { return nil }
        let storage = textView.textStorage
        guard storage.length > 0 else { return nil }
        let loc = min(textView.selectedRange.location, max(0, storage.length - 1))
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

    /// Remove the empty trailing body line and place a normal paragraph after the speaker section.
    private func exitSpeakerSection() {
        let result = SpeakerSectionEditing.exitSection(
            in: textView.textStorage,
            emptyBodyRange: paragraphRange()
        )
        textView.selectedRange = NSRange(location: result.caret, length: 0)
        textView.typingAttributes = result.typingAttributes
        emitChange()
        refreshSpeakerRails()
        scrollCaretVisible(animated: true)
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
        // Never restyle the speaker name header itself into a list/heading.
        if currentBlockType() == "speakerSection", type != "speakerSection" {
            insertSpeakerBodyParagraph()
            return
        }

        var range = paragraphRange()
        let storage = textView.textStorage
        let inSection = caretIsInsideSpeakerSection()

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
        var styled = NoteDocumentCodec.baseAttributesPublic(
            type: type,
            id: id,
            checked: checked,
            speakerId: nil,
            speakers: [:]
        )
        if inSection {
            styled = NoteDocumentCodec.applyingSpeakerSectionInset(styled)
        }

        // Strip any existing display-only list marker at the start of the paragraph.
        range = stripListMarker(in: range)

        let listNumber = numberedIndex(forParagraphStartingAt: range.location, promotingToNumbered: type == "numbered")
        if let marker = NoteDocumentCodec.listMarkerString(type: type, checked: checked, number: listNumber) {
            var markerAttrs = styled
            markerAttrs[NoteDocumentCodec.listMarkerKey] = true
            markerAttrs[.foregroundColor] = UIColor.secondaryLabel
            let markerAttr = NSAttributedString(string: marker, attributes: markerAttrs)
            storage.insert(markerAttr, at: range.location)
            range = NSRange(location: range.location, length: range.length + markerAttr.length)
            // Keep caret after the marker when the line was empty / caret at start.
            if textView.selectedRange.length == 0, textView.selectedRange.location <= range.location + markerAttr.length {
                textView.selectedRange = NSRange(location: range.location + markerAttr.length, length: 0)
            }
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
        if let checked {
            storage.addAttribute(NoteDocumentCodec.checkedKey, value: checked, range: range)
        } else {
            storage.removeAttribute(NoteDocumentCodec.checkedKey, range: range)
        }
        storage.removeAttribute(.backgroundColor, range: range)

        var typing = styled
        typing[NoteDocumentCodec.blockTypeKey] = type
        typing[NoteDocumentCodec.blockIdKey] = id
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
            storage.deleteCharacters(in: NSRange(location: range.location, length: markerLen))
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
        dismissTriggerMenu()
        delegate?.nativeNoteEditorRequestInsertBibleRef(self)
    }

    @objc private func presentSpeakerPicker() {
        dismissTriggerMenu()
        delegate?.nativeNoteEditorRequestSpeaker(self)
    }

    @objc private func undoEdit() {
        textView.undoManager?.undo()
        emitChange()
    }

    @objc private func redoEdit() {
        textView.undoManager?.redo()
        emitChange()
    }

    // MARK: - Hit testing (bible pills vs speaker / text)

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        dismissTriggerMenu()
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
            if (attrs[NoteDocumentCodec.blockTypeKey] as? String) == "speakerSection" {
                toggleSpeakerCollapsed(at: index)
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

    private func isSpecialTapTarget(at point: CGPoint) -> Bool {
        if bibleRef(at: point) != nil { return true }
        guard let index = characterIndex(at: point, requireHitBounds: false),
              index < textView.textStorage.length
        else { return false }
        let type = textView.textStorage.attributes(at: index, effectiveRange: nil)[NoteDocumentCodec.blockTypeKey] as? String
        return type == "speakerSection" || type == "check"
    }

    private func toggleSpeakerCollapsed(at index: Int) {
        // Capture full document (incl. expanded children) before flipping the flag.
        var doc = currentDocument()
        let ns = textView.textStorage.string as NSString
        let para = ns.paragraphRange(for: NSRange(location: index, length: 0))
        let attrs = textView.textStorage.attributes(at: para.location, effectiveRange: nil)
        let blockId = attrs[NoteDocumentCodec.blockIdKey] as? String
        guard let blockId,
              let matchIdx = doc.body.blocks.firstIndex(where: { $0.id == blockId && $0.type == "speakerSection" })
        else { return }
        var block = doc.body.blocks[matchIdx]
        let nextCollapsed = !(block.collapsed == true)
        block.collapsed = nextCollapsed ? true : nil
        doc.body.blocks[matchIdx] = block
        documentBase = doc
        applyingRemote = true
        let selected = textView.selectedRange
        let attributed = NoteDocumentCodec.attributedString(from: doc, speakers: speakers)
        textView.textStorage.setAttributedString(attributed)
        if let headerLoc = findSpeakerHeaderLocation(blockId: block.id) {
            textView.selectedRange = NSRange(location: headerLoc, length: 0)
        } else {
            textView.selectedRange = NSRange(location: min(selected.location, textView.textStorage.length), length: 0)
        }
        textView.typingAttributes = typingAttributesForCaret()
        applyingRemote = false
        refreshSpeakerRails()
        emitChange()
        V2NHaptics.selection()
        UIView.animate(withDuration: 0.22) {
            self.textView.layoutIfNeeded()
        }
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

    // MARK: - @ and / trigger menus

    private func caretAnchorPoint() -> CGPoint {
        let range = textView.selectedRange
        let start = min(range.location, max(0, textView.textStorage.length))
        var rect = textView.caretRect(for: textView.position(from: textView.beginningOfDocument, offset: start) ?? textView.endOfDocument)
        if rect.isNull || rect.isInfinite {
            rect = CGRect(x: textView.textContainerInset.left, y: textView.textContainerInset.top, width: 1, height: 20)
        }
        // Convert to this view's coordinates.
        return textView.convert(CGPoint(x: rect.minX, y: rect.maxY + 4), to: self)
    }

    private func showAtMenu(at location: Int) {
        textView.selectedRange = NSRange(location: location, length: 0)
        let items: [NoteEditorTriggerMenuView.Item] = speakers.map { speaker in
            NoteEditorTriggerMenuView.Item(
                id: speaker.id,
                title: speaker.name,
                systemImage: "person.fill",
                tint: UIColor(v2nHex: speaker.color)
            ) { [weak self] in
                guard let self else { return }
                self.insertSpeakerSection(speakerId: speaker.id, name: speaker.name)
            }
        } + [
            NoteEditorTriggerMenuView.Item(
                id: "__add__",
                title: String(localized: "Adicionar speaker"),
                systemImage: "plus",
                tint: V2NDesign.accent
            ) { [weak self] in
                self?.presentSpeakerPicker()
            },
        ]
        presentTriggerMenu(title: String(localized: "Speakers"), items: items)
    }

    private func showSlashMenu(at location: Int) {
        textView.selectedRange = NSRange(location: location, length: 0)
        // Original web `/` opened the bible picker; also offer common blocks (user expectation).
        let items: [NoteEditorTriggerMenuView.Item] = [
            .init(id: "ref", title: String(localized: "Referência bíblica"), systemImage: "book", tint: V2NDesign.accent) { [weak self] in
                self?.presentBibleRefPicker()
            },
            .init(id: "heading", title: String(localized: "Título"), systemImage: "textformat.size", tint: nil) { [weak self] in
                self?.dismissTriggerMenu()
                self?.applyBlockType("heading", preserveChecked: false)
            },
            .init(id: "bullet", title: String(localized: "Lista"), systemImage: "list.bullet", tint: nil) { [weak self] in
                self?.dismissTriggerMenu()
                self?.applyBlockType("bullet", preserveChecked: false)
            },
            .init(id: "numbered", title: String(localized: "Numerada"), systemImage: "list.number", tint: nil) { [weak self] in
                self?.dismissTriggerMenu()
                self?.applyBlockType("numbered", preserveChecked: false)
            },
            .init(id: "check", title: String(localized: "Checklist"), systemImage: "checklist", tint: nil) { [weak self] in
                self?.dismissTriggerMenu()
                self?.applyBlockType("check", preserveChecked: false)
            },
            .init(id: "quote", title: String(localized: "Citação"), systemImage: "text.quote", tint: nil) { [weak self] in
                self?.dismissTriggerMenu()
                self?.applyBlockType("quote", preserveChecked: false)
            },
            .init(id: "speaker", title: String(localized: "Speaker"), systemImage: "person.wave.2", tint: nil) { [weak self] in
                self?.presentSpeakerPicker()
            },
        ]
        presentTriggerMenu(title: String(localized: "Inserir"), items: items)
    }

    private func presentTriggerMenu(title: String, items: [NoteEditorTriggerMenuView.Item]) {
        dismissTriggerMenu()
        let menu = NoteEditorTriggerMenuView(title: title, items: items) { [weak self] in
            self?.dismissTriggerMenu()
        }
        menu.translatesAutoresizingMaskIntoConstraints = false
        addSubview(menu)
        triggerMenu = menu

        let width: CGFloat = min(280, bounds.width - 24)
        let leadingConstraint = menu.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12)
        let topConstraint = menu.topAnchor.constraint(equalTo: topAnchor, constant: 8)
        triggerMenuLeadingConstraint = leadingConstraint
        triggerMenuTopConstraint = topConstraint
        NSLayoutConstraint.activate([
            leadingConstraint,
            topConstraint,
            menu.widthAnchor.constraint(equalToConstant: width),
            menu.heightAnchor.constraint(lessThanOrEqualToConstant: 280),
        ])
        layoutIfNeeded()
        repositionTriggerMenuIfNeeded()
        V2NHaptics.selection()
    }

    private func repositionTriggerMenuIfNeeded() {
        guard let menu = triggerMenu else { return }
        let width = menu.bounds.width > 1 ? menu.bounds.width : min(280, bounds.width - 24)
        let height = menu.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        let caret = caretRectInSelf()
        let keyboardTop = bounds.height - keyboardOverlap
        let maxBottom = (keyboardOverlap > 0 ? keyboardTop : bounds.height) - 8
        // Prefer above the caret so the menu stays clear of the keyboard.
        var top = caret.minY - height - 8
        if top < 8 {
            top = min(caret.maxY + 6, maxBottom - height)
        }
        top = max(8, min(top, maxBottom - height))
        let leading = max(12, min(caret.minX, bounds.width - width - 12))
        triggerMenuTopConstraint?.constant = top
        triggerMenuLeadingConstraint?.constant = leading
        layoutIfNeeded()
    }

    private func caretRectInSelf() -> CGRect {
        let range = textView.selectedRange
        let start = min(range.location, max(0, textView.textStorage.length))
        var rect = textView.caretRect(for: textView.position(from: textView.beginningOfDocument, offset: start) ?? textView.endOfDocument)
        if rect.isNull || rect.isInfinite {
            rect = CGRect(x: textView.textContainerInset.left, y: textView.textContainerInset.top, width: 1, height: 20)
        }
        return textView.convert(rect, to: self)
    }

    private func dismissTriggerMenu() {
        triggerMenu?.removeFromSuperview()
        triggerMenu = nil
        triggerMenuTopConstraint = nil
        triggerMenuLeadingConstraint = nil
    }

    // MARK: - AppTests seams (real UITextView path)

    /// Prepare a frameless editor for AppTests. Avoid creating a second key `UIWindow` —
    /// AppTests run inside the app host and fighting SceneDelegate's window flakes/hangs CI.
    func testing_prepare(size: CGSize = CGSize(width: 390, height: 844)) {
        frame = CGRect(origin: .zero, size: size)
        textView.frame = bounds
        textView.textContainer.size = CGSize(width: size.width - 32, height: size.height)
        layoutIfNeeded()
    }

    /// Simulate a keyboard insertion the way UIKit does: ask `shouldChangeTextIn`, then
    /// either let our handler mutate storage (Return → false) or apply typingAttributes (true).
    func testing_insertText(_ string: String) {
        let range = textView.selectedRange
        let allowed = textView(textView, shouldChangeTextIn: range, replacementText: string)
        guard allowed else { return }
        let attrs = textView.typingAttributes
        let piece = NSAttributedString(string: string, attributes: attrs)
        textView.textStorage.replaceCharacters(in: range, with: piece)
        textView.selectedRange = NSRange(location: range.location + piece.length, length: 0)
        textViewDidChange(textView)
    }

    func testing_selectedRange() -> NSRange {
        textView.selectedRange
    }

    func testing_setSelectedRange(_ range: NSRange) {
        let length = textView.textStorage.length
        let loc = min(max(0, range.location), length)
        let len = min(max(0, range.length), max(0, length - loc))
        textView.selectedRange = NSRange(location: loc, length: len)
        ensureTypingAttributes()
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
        if insideSpeaker {
            if paragraphEmpty {
                if blockType == "bullet" || blockType == "numbered" || blockType == "check" || blockType == "quote" {
                    return .demoteListToParagraph
                }
                if isLastBodyOfSection {
                    return .exitSection
                }
            }
            // Non-empty body Enter, or empty non-last body → stay inside with a real body run.
            return .continueInSection
        }
        if blockType == "bullet" || blockType == "numbered" || blockType == "check" || blockType == "quote" {
            return .continueList(blockType)
        }
        return .defaultNewline
    }
}

// MARK: - Text view (caret height = font line height)

/// Clamps the caret to the font line height so `paragraphSpacing` does not stretch the cursor.
final class NoteEditorTextView: UITextView {
    override func caretRect(for position: UITextPosition) -> CGRect {
        var rect = super.caretRect(for: position)
        let font = caretFont(at: position)
        let lineHeight = ceil(font.lineHeight)
        if rect.height > lineHeight + 0.5 {
            rect.size.height = lineHeight
        }
        return rect
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

// MARK: - Inline @ / / popup

@MainActor
final class NoteEditorTriggerMenuView: UIView, UITableViewDelegate, UITableViewDataSource {
    struct Item {
        let id: String
        let title: String
        let systemImage: String
        let tint: UIColor?
        let action: () -> Void
    }

    private let items: [Item]
    private let onDismiss: () -> Void
    private let table = UITableView(frame: .zero, style: .plain)
    private let titleLabel = UILabel()

    init(title: String, items: [Item], onDismiss: @escaping () -> Void) {
        self.items = items
        self.onDismiss = onDismiss
        super.init(frame: .zero)
        backgroundColor = V2NDesign.surface
        layer.cornerRadius = V2NDesign.Radius.md
        layer.cornerCurve = .continuous
        layer.borderWidth = 0.5
        layer.borderColor = V2NDesign.separator.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: 4)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        titleLabel.font = V2NDesign.caption()
        titleLabel.textColor = .secondaryLabel

        table.translatesAutoresizingMaskIntoConstraints = false
        table.delegate = self
        table.dataSource = self
        table.register(UITableViewCell.self, forCellReuseIdentifier: "row")
        table.backgroundColor = .clear
        table.separatorInset = UIEdgeInsets(top: 0, left: 44, bottom: 0, right: 0)
        table.rowHeight = 44
        table.isScrollEnabled = items.count > 6

        addSubview(titleLabel)
        addSubview(table)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),

            table.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            table.leadingAnchor.constraint(equalTo: leadingAnchor),
            table.trailingAnchor.constraint(equalTo: trailingAnchor),
            table.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            table.heightAnchor.constraint(equalToConstant: CGFloat(min(items.count, 6)) * 44),
        ])
        accessibilityViewIsModal = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
        let item = items[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = item.title
        config.image = UIImage(systemName: item.systemImage)
        config.imageProperties.tintColor = item.tint ?? V2NDesign.accent
        config.textProperties.font = V2NDesign.preferred(.body, weight: .medium)
        cell.contentConfiguration = config
        cell.backgroundColor = .clear
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = items[indexPath.row]
        onDismiss()
        item.action()
    }
}

// MARK: - Compact keyboard accessory (scrollable + Liquid Glass)

@MainActor
final class NoteEditorAccessoryBar: UIView {
    enum Action {
        case bold, italic, underline, strike
        case heading, bullet, numbered, check, quote
        case bibleRef, speaker, undo, redo
    }

    var onAction: ((Action) -> Void)?

    private let blur: UIVisualEffectView
    private let scroll = UIScrollView()
    private let stack = UIStackView()

    init() {
        let effect = V2NGlassMaterial.effect(withInteractive: true) ?? UIBlurEffect(style: .systemChromeMaterial)
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

        let groups: [[(String, Action, String)]] = [
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
            [
                ("book", .bibleRef, String(localized: "Referência bíblica")),
                ("person.wave.2", .speaker, String(localized: "Speaker")),
                ("arrow.uturn.backward", .undo, String(localized: "Desfazer")),
                ("arrow.uturn.forward", .redo, String(localized: "Refazer")),
            ],
        ]

        for (groupIndex, group) in groups.enumerated() {
            if groupIndex > 0 {
                let sep = UIView()
                sep.translatesAutoresizingMaskIntoConstraints = false
                sep.backgroundColor = V2NDesign.separator
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
        hairline.backgroundColor = V2NDesign.separator
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
        config.baseForegroundColor = V2NDesign.accent
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
}
