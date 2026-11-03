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
    private let toolbar = UIToolbar()
    private var documentBase: NativeAPIClient.NoteDocument = NativeAPIClient.emptyNote(id: "pending")
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
        textView.accessibilityLabel = "Corpo da nota"
        textView.accessibilityHint = "A primeira linha é o título"
        addSubview(textView)

        toolbar.sizeToFit()
        toolbar.tintColor = V2NDesign.accent
        toolbar.items = makeToolbarItems()
        textView.inputAccessoryView = toolbar

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

    private func makeToolbarItems() -> [UIBarButtonItem] {
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        return [
            toolbarItem("textformat.size", #selector(toggleHeading), "Título"),
            toolbarItem("list.bullet", #selector(toggleBullet), "Lista"),
            toolbarItem("list.number", #selector(toggleNumbered), "Numerada"),
            toolbarItem("checklist", #selector(toggleCheck), "Checklist"),
            toolbarItem("text.quote", #selector(toggleQuote), "Citação"),
            flex,
            toolbarItem("bold", #selector(toggleBoldMark), "Negrito"),
            toolbarItem("italic", #selector(toggleItalicMark), "Itálico"),
            toolbarItem("underline", #selector(toggleUnderlineMark), "Sublinhado"),
            toolbarItem("strikethrough", #selector(toggleStrikeMark), "Riscado"),
            flex,
            toolbarItem("book", #selector(presentBibleRefPicker), "Referência bíblica"),
            toolbarItem("person.wave.2", #selector(presentSpeakerPicker), "Speaker"),
            toolbarItem("arrow.uturn.backward", #selector(undoEdit), "Desfazer"),
            toolbarItem("arrow.uturn.forward", #selector(redoEdit), "Refazer"),
        ]
    }

    private func toolbarItem(_ systemName: String, _ action: Selector, _ label: String) -> UIBarButtonItem {
        let button = UIBarButtonItem(image: UIImage(systemName: systemName), style: .plain, target: self, action: action)
        button.accessibilityLabel = label
        return button
    }

    /// Load / replace the document currently shown.
    func pushNote(_ note: NativeAPIClient.NoteDocument, speakers _: [NativeAPIClient.SpeakerDTO] = [], readOnly: Bool = false) {
        precondition(Thread.isMainThread)
        documentBase = note
        applyingRemote = true
        let attributed = NoteDocumentCodec.attributedString(from: note)
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
        let label = NoteDocumentCodec.displayText(for: ref)
        var attrs = textView.typingAttributes
        attrs[.foregroundColor] = V2NDesign.bookmark
        attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        attrs[NoteDocumentCodec.bibleRefKey] = ref
        let piece = NSAttributedString(string: label, attributes: attrs)
        textView.textStorage.replaceCharacters(in: textView.selectedRange, with: piece)
        let end = textView.selectedRange.location + piece.length
        textView.selectedRange = NSRange(location: end, length: 0)
        textView.typingAttributes = baseTypingAttributes()
        emitChange()
    }

    // MARK: - UITextViewDelegate

    func textViewDidChange(_ textView: UITextView) {
        guard !applyingRemote else { return }
        emitChange()
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if text == "\n" {
            // Continue list / checklist styles on the new paragraph.
            let type = currentBlockType()
            DispatchQueue.main.async { [weak self] in
                self?.applyBlockType(type, preserveChecked: true)
            }
        }
        return true
    }

    private func emitChange() {
        let doc = currentDocument()
        documentBase = doc
        delegate?.nativeNoteEditorDidChange(self, document: doc)
    }

    // MARK: - Formatting

    private func baseTypingAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: UIFont.preferredFont(forTextStyle: .body),
            .foregroundColor: UIColor.label,
            NoteDocumentCodec.blockTypeKey: currentBlockType(),
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
        let id = currentBlockId()
        textView.textStorage.enumerateAttributes(in: range, options: []) { _, sub, _ in
            textView.textStorage.addAttribute(NoteDocumentCodec.blockTypeKey, value: type, range: sub)
            textView.textStorage.addAttribute(NoteDocumentCodec.blockIdKey, value: id, range: sub)
            if let checked {
                textView.textStorage.addAttribute(NoteDocumentCodec.checkedKey, value: checked, range: sub)
            } else {
                textView.textStorage.removeAttribute(NoteDocumentCodec.checkedKey, range: sub)
            }
        }
        // Font / indent refresh for the paragraph.
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
            // Toggle checked state when already a checklist line.
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

    // Named *Mark / *Edit to avoid colliding with UIResponderStandardEditActions
    // (toggleBoldface / toggleUnderline / undo / redo).
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
        if let ref = attrs[NoteDocumentCodec.bibleRefKey] as? NoteDocumentCodec.BibleRefPayload {
            delegate?.nativeNoteEditor(self, openBibleRef: ref)
            return
        }
        if let type = attrs[NoteDocumentCodec.blockTypeKey] as? String, type == "check" {
            // Toggle checkbox near the start of the line.
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
