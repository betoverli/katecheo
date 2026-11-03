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

    private let textView = UITextView()
    private let accessory = NoteEditorAccessoryBar()
    private var documentBase: NativeAPIClient.NoteDocument = NativeAPIClient.emptyNote(id: "pending")
    private var speakers: [NativeAPIClient.SpeakerDTO] = []
    private var applyingRemote = false
    private(set) var isReady = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        precondition(Thread.isMainThread, "NativeNoteEditorView must be created on the main thread")
        backgroundColor = V2NDesign.canvas

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.delegate = self
        textView.backgroundColor = V2NDesign.canvas
        textView.textContainerInset = UIEdgeInsets(top: V2NDesign.Space.md, left: V2NDesign.Space.md, bottom: V2NDesign.Space.lg, right: V2NDesign.Space.md)
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
        textView.inputAccessoryView = accessory

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.delegate = self
        textView.addGestureRecognizer(tap)
    }

    /// Load / replace the document currently shown.
    func pushNote(_ note: NativeAPIClient.NoteDocument, speakers: [NativeAPIClient.SpeakerDTO] = [], readOnly: Bool = false) {
        precondition(Thread.isMainThread)
        documentBase = note
        self.speakers = speakers
        applyingRemote = true
        let attributed = NoteDocumentCodec.attributedString(from: note, speakers: speakers)
        textView.attributedText = attributed
        textView.selectedRange = NSRange(location: 0, length: 0)
        textView.isEditable = !readOnly
        applyingRemote = false
        isReady = true
    }

    func currentDocument() -> NativeAPIClient.NoteDocument {
        precondition(Thread.isMainThread)
        return NoteDocumentCodec.document(from: textView.attributedText ?? NSAttributedString(), base: documentBase)
    }

    func insertBibleRef(_ ref: NoteDocumentCodec.BibleRefPayload) {
        precondition(Thread.isMainThread)
        var base = textView.typingAttributes
        base[NoteDocumentCodec.blockTypeKey] = currentBlockType()
        base[NoteDocumentCodec.blockIdKey] = currentBlockId()
        let piece = NoteDocumentCodec.bibleRefPill(payload: ref, base: base)
        textView.textStorage.replaceCharacters(in: textView.selectedRange, with: piece)
        let end = textView.selectedRange.location + piece.length
        textView.selectedRange = NSRange(location: end, length: 0)
        textView.typingAttributes = baseTypingAttributes()
        emitChange()
    }

    func insertSpeakerSection(speakerId: String, name: String) {
        precondition(Thread.isMainThread)
        let id = NoteDocumentCodec.newId()
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = 14
        style.headIndent = 12
        style.firstLineHeadIndent = 12
        let color = speakers.first(where: { $0.id == speakerId }).flatMap { UIColor(v2nHex: $0.color) }
            ?? UIColor(red: 0.77, green: 0.65, blue: 0.45, alpha: 1)
        let header = NSAttributedString(string: name, attributes: [
            .font: V2NDesign.preferred(.title3, weight: .semibold),
            .foregroundColor: color,
            .backgroundColor: V2NDesign.accentSoft,
            .paragraphStyle: style,
            NoteDocumentCodec.blockTypeKey: "speakerSection",
            NoteDocumentCodec.blockIdKey: id,
            NoteDocumentCodec.speakerIdKey: speakerId,
        ])
        let bodyStyle = NSMutableParagraphStyle()
        bodyStyle.lineSpacing = 3
        let body = NSAttributedString(string: "\n", attributes: [
            .font: UIFont.preferredFont(forTextStyle: .body),
            .foregroundColor: UIColor.label,
            .paragraphStyle: bodyStyle,
            NoteDocumentCodec.blockTypeKey: "paragraph",
            NoteDocumentCodec.blockIdKey: NoteDocumentCodec.newId(),
        ])
        let chunk = NSMutableAttributedString()
        if textView.selectedRange.location > 0, textView.textStorage.length > 0 {
            chunk.append(NSAttributedString(string: "\n"))
        }
        chunk.append(header)
        chunk.append(body)
        textView.textStorage.replaceCharacters(in: textView.selectedRange, with: chunk)
        let end = (textView.selectedRange.location) + chunk.length
        textView.selectedRange = NSRange(location: end, length: 0)
        emitChange()
    }

    // MARK: - UITextViewDelegate

    func textViewDidChange(_ textView: UITextView) {
        guard !applyingRemote else { return }
        emitChange()
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if text == "\n" {
            let type = currentBlockType()
            if type == "speakerSection" {
                DispatchQueue.main.async { [weak self] in
                    self?.applyBlockType("paragraph", preserveChecked: false)
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.applyBlockType(type, preserveChecked: true)
                }
            }
        }
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
        case .undo: undoEdit()
        case .redo: redoEdit()
        }
    }

    // MARK: - Formatting

    private func baseTypingAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: UIFont.preferredFont(forTextStyle: .body),
            .foregroundColor: UIColor.label,
            NoteDocumentCodec.blockTypeKey: currentBlockType() == "speakerSection" ? "paragraph" : currentBlockType(),
            NoteDocumentCodec.blockIdKey: currentBlockId(),
        ]
    }

    private func currentBlockType() -> String {
        guard textView.attributedText.length > 0 else { return "paragraph" }
        let loc = min(textView.selectedRange.location, max(0, textView.attributedText.length - 1))
        let attrs = textView.attributedText.attributes(at: loc, effectiveRange: nil)
        return (attrs[NoteDocumentCodec.blockTypeKey] as? String) ?? "paragraph"
    }

    private func currentBlockId() -> String {
        guard textView.attributedText.length > 0 else { return NoteDocumentCodec.newId() }
        let loc = min(textView.selectedRange.location, max(0, textView.attributedText.length - 1))
        let attrs = textView.attributedText.attributes(at: loc, effectiveRange: nil)
        return (attrs[NoteDocumentCodec.blockIdKey] as? String) ?? NoteDocumentCodec.newId()
    }

    private func paragraphRange() -> NSRange {
        let ns = textView.text as NSString
        let loc = min(textView.selectedRange.location, ns.length)
        return ns.paragraphRange(for: NSRange(location: loc, length: 0))
    }

    private func applyBlockType(_ type: String, preserveChecked: Bool) {
        let range = paragraphRange()
        guard range.length >= 0, textView.textStorage.length >= range.location else { return }
        let checked: Bool?
        if type == "check" {
            if preserveChecked, range.length > 0 {
                let attrs = textView.textStorage.attributes(at: range.location, effectiveRange: nil)
                checked = (attrs[NoteDocumentCodec.checkedKey] as? Bool) ?? false
            } else {
                checked = false
            }
        } else {
            checked = nil
        }
        let id = NoteDocumentCodec.newId()
        textView.textStorage.enumerateAttributes(in: range, options: []) { _, sub, _ in
            textView.textStorage.addAttribute(NoteDocumentCodec.blockTypeKey, value: type, range: sub)
            textView.textStorage.addAttribute(NoteDocumentCodec.blockIdKey, value: id, range: sub)
            if let checked {
                textView.textStorage.addAttribute(NoteDocumentCodec.checkedKey, value: checked, range: sub)
            } else {
                textView.textStorage.removeAttribute(NoteDocumentCodec.checkedKey, range: sub)
            }
        }
        let font: UIFont
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        switch type {
        case "heading":
            font = UIFont.preferredFont(forTextStyle: .title2)
        case "quote":
            font = UIFont.preferredFont(forTextStyle: .body)
            style.headIndent = 16
            style.firstLineHeadIndent = 16
        case "bullet", "numbered", "check":
            font = UIFont.preferredFont(forTextStyle: .body)
            style.headIndent = 22
        default:
            font = UIFont.preferredFont(forTextStyle: .body)
        }
        if range.length > 0 {
            textView.textStorage.addAttribute(.font, value: font, range: range)
            textView.textStorage.addAttribute(.paragraphStyle, value: style, range: range)
            textView.textStorage.removeAttribute(.backgroundColor, range: range)
            textView.textStorage.addAttribute(.foregroundColor, value: UIColor.label, range: range)
        }
        var typing = textView.typingAttributes
        typing[NoteDocumentCodec.blockTypeKey] = type
        typing[NoteDocumentCodec.blockIdKey] = id
        typing[.font] = font
        typing[.paragraphStyle] = style
        if let checked { typing[NoteDocumentCodec.checkedKey] = checked }
        textView.typingAttributes = typing
        emitChange()
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
            let range = paragraphRange()
            if range.length > 0 {
                let attrs = textView.textStorage.attributes(at: range.location, effectiveRange: nil)
                let checked = !((attrs[NoteDocumentCodec.checkedKey] as? Bool) ?? false)
                textView.textStorage.addAttribute(NoteDocumentCodec.checkedKey, value: checked, range: range)
                emitChange()
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

    @objc private func undoEdit() {
        textView.undoManager?.undo()
        emitChange()
    }

    @objc private func redoEdit() {
        textView.undoManager?.redo()
        emitChange()
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let point = gesture.location(in: textView)
        var fraction: CGFloat = 0
        let index = textView.layoutManager.characterIndex(
            for: point,
            in: textView.textContainer,
            fractionOfDistanceBetweenInsertionPoints: &fraction
        )
        guard index < textView.textStorage.length else { return }
        let attrs = textView.textStorage.attributes(at: index, effectiveRange: nil)
        if let attachment = attrs[.attachment] as? BibleRefPillAttachment {
            delegate?.nativeNoteEditor(self, openBibleRef: attachment.payload)
            return
        }
        if let ref = attrs[NoteDocumentCodec.bibleRefKey] as? NoteDocumentCodec.BibleRefPayload {
            delegate?.nativeNoteEditor(self, openBibleRef: ref)
            return
        }
        if let type = attrs[NoteDocumentCodec.blockTypeKey] as? String, type == "check" {
            let range = (textView.text as NSString).paragraphRange(for: NSRange(location: index, length: 0))
            let checked = !((attrs[NoteDocumentCodec.checkedKey] as? Bool) ?? false)
            textView.textStorage.addAttribute(NoteDocumentCodec.checkedKey, value: checked, range: range)
            emitChange()
        }
    }
}

extension NativeNoteEditorView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
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
