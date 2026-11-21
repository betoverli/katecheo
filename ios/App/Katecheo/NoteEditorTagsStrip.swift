import UIKit

/// Editable tag chips shown under the note title inside the editor (TF210).
/// The note-level speaker chip leads the same horizontal strip so it scrolls with content.
@MainActor
final class NoteEditorTagsStrip: UIView, UITextFieldDelegate, UIScrollViewDelegate {
    static let preferredHeight: CGFloat = 32
    /// Fixed soft-clip width at the strip edges (points). Mask is static on the container.
    private static let edgeFadeWidth: CGFloat = 28

    var onTagsChange: (([String]) -> Void)?
    var onEditingChange: ((Bool) -> Void)?
    /// Opens the whole-note speaker picker (does not add tags).
    var onSpeakerTap: (() -> Void)?

    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let addField = UITextField()
    private let placeholderButton = UIButton(type: .system)
    private let speakerChip = UIButton(type: .system)
    /// Container-level mask so chips scroll under a fixed soft edge (never animate per-tag alpha).
    private let edgeFadeMask = CAGradientLayer()
    private var showsLeadingFade = false
    private var showsTrailingFade = false
    private var tags: [String] = []
    private var speakerName: String?
    private(set) var isEditingTags = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        backgroundColor = .clear
        isOpaque = false

        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = true
        scroll.delegate = self
        // Kill iOS 26 scroll-edge soft reveal — that reads as appear-on-scroll for chips.
        KCGlassMaterial.prepareWebScrollView(scroll)
        addSubview(scroll)

        edgeFadeMask.startPoint = CGPoint(x: 0, y: 0.5)
        edgeFadeMask.endPoint = CGPoint(x: 1, y: 0.5)
        // Mask the strip container (not the scroll layer): fade stays fixed in screen space.
        layer.mask = edgeFadeMask

        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        speakerChip.translatesAutoresizingMaskIntoConstraints = false
        speakerChip.setContentHuggingPriority(.required, for: .horizontal)
        speakerChip.setContentCompressionResistancePriority(.required, for: .horizontal)
        speakerChip.addTarget(self, action: #selector(speakerTapped), for: .touchUpInside)
        speakerChip.accessibilityIdentifier = "note.tagsStrip.speaker"

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

    override func layoutSubviews() {
        super.layoutSubviews()
        // Keep mask sized to the container bounds (not contentOffset).
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        edgeFadeMask.frame = bounds
        CATransaction.commit()
        refreshEdgeFadeState(force: true)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // Only toggle leading/trailing on/off — never animate alpha or move fade amount with scroll.
        refreshEdgeFadeState(force: false)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        refreshEdgeFadeState(force: false)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { refreshEdgeFadeState(force: false) }
    }

    /// Static soft-clip mask: trailing when content overflows (and more remains),
    /// leading when scrolled away from start. Updates without Core Animation.
    private func refreshEdgeFadeState(force: Bool) {
        let visibleWidth = bounds.width
        let contentWidth = scroll.contentSize.width
        let overflow = visibleWidth > 1 && contentWidth > visibleWidth + 0.5
        let inset = scroll.adjustedContentInset
        let minX = -inset.left
        let maxX = max(minX, contentWidth - visibleWidth + inset.right)
        let x = scroll.contentOffset.x
        let leadOn = overflow && x > minX + 0.5
        let trailOn = overflow && x < maxX - 0.5
        guard force || leadOn != showsLeadingFade || trailOn != showsTrailingFade else { return }
        showsLeadingFade = leadOn
        showsTrailingFade = trailOn
        applyEdgeFadeMask()
    }

    private func applyEdgeFadeMask() {
        let width = max(bounds.width, 1)
        let fade = min(Self.edgeFadeWidth / width, 0.45)
        let leadEnd = NSNumber(value: showsLeadingFade ? fade : 0)
        let trailStart = NSNumber(value: showsTrailingFade ? (1 - fade) : 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        edgeFadeMask.colors = [
            (showsLeadingFade ? UIColor.clear : UIColor.black).cgColor,
            UIColor.black.cgColor,
            UIColor.black.cgColor,
            (showsTrailingFade ? UIColor.clear : UIColor.black).cgColor,
        ]
        edgeFadeMask.locations = [0, leadEnd, trailStart, 1]
        CATransaction.commit()
    }

    func setTags(_ next: [String]) {
        guard tags != next else { return }
        tags = next
        rebuild()
    }

    /// `nil` / empty → compact “add speaker” chip; otherwise person + name.
    func setSpeakerName(_ name: String?) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = (trimmed?.isEmpty == false) ? trimmed : nil
        guard speakerName != next else {
            // Still refresh colors/fonts if traits changed while name stayed the same.
            configureSpeakerChip()
            return
        }
        speakerName = next
        rebuild()
    }

    func currentTags() -> [String] { tags }

    @objc private func speakerTapped() {
        onSpeakerTap?()
    }

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
        configureSpeakerChip()
        stack.addArrangedSubview(speakerChip)
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
        setNeedsLayout()
        // Content width may change after rebuild — refresh overflow fades without animation.
        DispatchQueue.main.async { [weak self] in
            self?.refreshEdgeFadeState(force: true)
        }
    }

    private func configureSpeakerChip() {
        var config = UIButton.Configuration.plain()
        if let speakerName {
            config.title = speakerName
            config.image = UIImage(systemName: "person.fill")
            speakerChip.accessibilityLabel = "\(String(localized: "Speaker da nota")): \(speakerName)"
        } else {
            config.title = String(localized: "Speaker")
            config.image = UIImage(systemName: "person.badge.plus")
            speakerChip.accessibilityLabel = String(localized: "Speaker da nota")
        }
        config.imagePlacement = .leading
        config.imagePadding = 5
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        config.baseForegroundColor = KCDesign.accent
        // Match tag-chip vertical rhythm; accentSoft fill like KCSpeakerChipView.
        config.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10)
        config.background.backgroundColor = KCDesign.accentSoft
        config.background.cornerRadius = 12
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var next = incoming
            next.font = KCDesign.preferred(.footnote, weight: .semibold)
            return next
        }
        speakerChip.configuration = config
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

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            configureSpeakerChip()
            // Tag chips are rebuilt with accent colors; only refresh if already laid out.
            if !tags.isEmpty || speakerName != nil {
                rebuild()
            }
        }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.preferredHeight)
    }

    // MARK: - Testing hooks

    var testing_speakerTitle: String? {
        speakerChip.configuration?.title
    }

    var testing_hasAssignedSpeaker: Bool {
        speakerName != nil
    }

    var testing_speakerChipView: UIView { speakerChip }

    var testing_firstArrangedIsSpeaker: Bool {
        stack.arrangedSubviews.first === speakerChip
    }

    func testing_tapSpeaker() {
        speakerTapped()
    }

    var testing_scrollView: UIScrollView { scroll }

    /// Mask lives on the strip container, not the scroll view (avoids scroll-driven reveal).
    var testing_maskIsOnContainer: Bool { layer.mask === edgeFadeMask && scroll.layer.mask == nil }

    func testing_updateEdgeFadeMask() {
        layoutIfNeeded()
        refreshEdgeFadeState(force: true)
    }

    /// True when the trailing edge fade is active (more content to the right).
    var testing_trailingFadeActive: Bool { showsTrailingFade }

    /// True when the leading edge fade is active (scrolled away from start).
    var testing_leadingFadeActive: Bool { showsLeadingFade }

    var testing_edgeFadeWidth: CGFloat { Self.edgeFadeWidth }
}
