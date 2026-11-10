import UIKit

/// Editable tag chips shown under the note title inside the editor (TF210).
@MainActor
final class NoteEditorTagsStrip: UIView, UITextFieldDelegate {
    static let preferredHeight: CGFloat = 32

    var onTagsChange: (([String]) -> Void)?
    var onEditingChange: ((Bool) -> Void)?

    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let addField = UITextField()
    private let placeholderButton = UIButton(type: .system)
    private var tags: [String] = []
    private(set) var isEditingTags = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        backgroundColor = .clear

        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = true
        addSubview(scroll)

        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        placeholderButton.translatesAutoresizingMaskIntoConstraints = false
        var placeholderConfig = UIButton.Configuration.plain()
        placeholderConfig.title = String(localized: "Adicionar tags")
        placeholderConfig.baseForegroundColor = .tertiaryLabel
        placeholderConfig.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 8)
        placeholderConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var next = incoming
            next.font = KCDesign.preferred(.subheadline, weight: .regular)
            return next
        }
        placeholderButton.configuration = placeholderConfig
        placeholderButton.addTarget(self, action: #selector(beginAddingTag), for: .touchUpInside)
        placeholderButton.accessibilityLabel = String(localized: "Adicionar tags")

        addField.translatesAutoresizingMaskIntoConstraints = false
        addField.placeholder = String(localized: "Nova tag")
        addField.font = KCDesign.preferred(.subheadline, weight: .regular)
        addField.textColor = .label
        addField.tintColor = KCDesign.accent
        addField.borderStyle = .none
        addField.autocapitalizationType = .none
        addField.autocorrectionType = .no
        addField.returnKeyType = .done
        addField.delegate = self
        addField.addTarget(self, action: #selector(addFieldEditingChanged), for: .editingChanged)
        addField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        addField.widthAnchor.constraint(greaterThanOrEqualToConstant: 96).isActive = true
        addField.isHidden = true

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.heightAnchor.constraint(equalToConstant: Self.preferredHeight),

            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])

        rebuild()
    }

    func setTags(_ next: [String]) {
        guard tags != next else { return }
        tags = next
        rebuild()
    }

    func currentTags() -> [String] { tags }

    @objc private func beginAddingTag() {
        placeholderButton.isHidden = true
        addField.isHidden = false
        if addField.superview == nil {
            stack.addArrangedSubview(addField)
        }
        setEditing(true)
        addField.becomeFirstResponder()
    }

    private func setEditing(_ editing: Bool) {
        guard isEditingTags != editing else { return }
        isEditingTags = editing
        onEditingChange?(editing)
    }

    @objc private func addFieldEditingChanged() {
        // Keep chrome in sync while typing a new tag.
        if addField.isFirstResponder { setEditing(true) }
    }

    private func commitAddField() {
        let raw = (addField.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        addField.text = ""
        addField.resignFirstResponder()
        addField.isHidden = true
        setEditing(false)
        if !raw.isEmpty {
            let tag = String(raw.prefix(24))
            if !tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
                tags.append(tag)
                onTagsChange?(tags)
            }
        }
        rebuild()
    }

    private func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
        onTagsChange?(tags)
        rebuild()
    }

    private func rebuild() {
        stack.arrangedSubviews.forEach { view in
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for tag in tags {
            stack.addArrangedSubview(makeChip(tag))
        }
        if addField.isFirstResponder {
            addField.isHidden = false
            stack.addArrangedSubview(addField)
            placeholderButton.isHidden = true
        } else if tags.isEmpty {
            placeholderButton.isHidden = false
            stack.addArrangedSubview(placeholderButton)
            addField.isHidden = true
        } else {
            let add = UIButton(type: .system)
            var config = UIButton.Configuration.plain()
            config.image = UIImage(systemName: "plus")
            config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            config.baseForegroundColor = KCDesign.accent
            config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
            add.configuration = config
            add.accessibilityLabel = String(localized: "Adicionar tags")
            add.addTarget(self, action: #selector(beginAddingTag), for: .touchUpInside)
            stack.addArrangedSubview(add)
            placeholderButton.isHidden = true
            addField.isHidden = true
        }
    }

    private func makeChip(_ tag: String) -> UIView {
        let chip = UIButton(type: .system)
        var config = UIButton.Configuration.plain()
        config.title = "#\(tag)"
        config.image = UIImage(systemName: "xmark")
        config.imagePlacement = .trailing
        config.imagePadding = 6
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        config.baseForegroundColor = KCDesign.accent
        config.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 8)
        config.background.backgroundColor = KCDesign.accent.withAlphaComponent(0.12)
        config.background.cornerRadius = 12
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var next = incoming
            next.font = KCDesign.preferred(.footnote, weight: .medium)
            return next
        }
        chip.configuration = config
        chip.accessibilityLabel = "\(String(localized: "Remover tag")) \(tag)"
        chip.addAction(UIAction { [weak self] _ in
            self?.removeTag(tag)
        }, for: .touchUpInside)
        return chip
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        setEditing(true)
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        if textField === addField {
            commitAddField()
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        commitAddField()
        return false
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.preferredHeight)
    }
}
