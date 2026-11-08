import UIKit

// MARK: - Empty / error / loading

/// Centered empty/error/loading state with SF Symbol + pt-BR copy.
final class V2NEmptyStateView: UIView {
    private let stack = UIStackView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private var actionHandler: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = false
        translatesAutoresizingMaskIntoConstraints = false
        isHidden = true

        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = V2NDesign.Space.sm
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let iconWrap = UIView()
        iconWrap.translatesAutoresizingMaskIntoConstraints = false
        iconWrap.backgroundColor = V2NDesign.accentSoft
        iconWrap.layer.cornerRadius = V2NDesign.Radius.lg
        iconWrap.layer.cornerCurve = .continuous

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = V2NDesign.accent
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 28, weight: .medium)
        iconWrap.addSubview(iconView)

        titleLabel.font = V2NDesign.headline()
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.adjustsFontForContentSizeCategory = true

        messageLabel.font = V2NDesign.rowSubtitle()
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.adjustsFontForContentSizeCategory = true

        var config = UIButton.Configuration.filled()
        config.cornerStyle = .large
        config.baseBackgroundColor = V2NDesign.accent
        config.baseForegroundColor = .white
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var out = incoming
            out.font = V2NDesign.headline()
            return out
        }
        actionButton.configuration = config
        actionButton.addTarget(self, action: #selector(tapAction), for: .touchUpInside)
        actionButton.isHidden = true

        stack.addArrangedSubview(iconWrap)
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(messageLabel)
        stack.addArrangedSubview(actionButton)
        stack.setCustomSpacing(V2NDesign.Space.md, after: messageLabel)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -12),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: V2NDesign.Space.lg),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -V2NDesign.Space.lg),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 320),

            iconWrap.widthAnchor.constraint(equalToConstant: 72),
            iconWrap.heightAnchor.constraint(equalToConstant: 72),
            iconView.centerXAnchor.constraint(equalTo: iconWrap.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconWrap.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(
        symbol: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        iconView.image = UIImage(systemName: symbol)
        titleLabel.text = title
        messageLabel.text = message
        messageLabel.isHidden = message.isEmpty
        actionHandler = action
        if let actionTitle, action != nil {
            actionButton.configuration?.title = actionTitle
            actionButton.isHidden = false
            actionButton.accessibilityLabel = actionTitle
        } else {
            actionButton.isHidden = true
            actionHandler = nil
        }
        accessibilityElements = [iconView, titleLabel, messageLabel, actionButton].filter { !$0.isHidden }
        iconView.isAccessibilityElement = true
        iconView.accessibilityLabel = title
        isHidden = false
        alpha = 0
        transform = CGAffineTransform(translationX: 0, y: 8)
        UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            self.alpha = 1
            self.transform = .identity
        }
    }

    func showLoading(message: String = String(localized: "Carregando…")) {
        show(symbol: "arrow.triangle.2.circlepath", title: message, message: "")
        // Gentle pulse while loading.
        iconView.layer.removeAnimation(forKey: "spin")
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = CGFloat.pi * 2
        spin.duration = 1.1
        spin.repeatCount = .infinity
        iconView.layer.add(spin, forKey: "spin")
    }

    func hide() {
        iconView.layer.removeAnimation(forKey: "spin")
        isHidden = true
        alpha = 1
        transform = .identity
    }

    @objc private func tapAction() {
        V2NHaptics.light()
        actionHandler?()
    }
}

// MARK: - Status banner

final class V2NStatusBanner: UILabel {
    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        font = V2NDesign.caption()
        textColor = .secondaryLabel
        textAlignment = .center
        numberOfLines = 2
        adjustsFontForContentSizeCategory = true
        accessibilityTraits = .updatesFrequently
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setStatus(_ text: String?, kind: Kind = .neutral) {
        self.text = text
        switch kind {
        case .neutral: textColor = .secondaryLabel
        case .success: textColor = V2NDesign.accent
        case .warning: textColor = .systemOrange
        case .error: textColor = V2NDesign.danger
        }
    }

    enum Kind { case neutral, success, warning, error }
}

// MARK: - Primary / secondary buttons

enum V2NButtonStyle {
    static func applyPrimary(to button: UIButton, title: String) {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.baseBackgroundColor = V2NDesign.accent
        config.baseForegroundColor = .white
        config.cornerStyle = .large
        config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var out = incoming
            out.font = V2NDesign.headline()
            return out
        }
        button.configuration = config
        button.accessibilityLabel = title
    }

    static func applySecondary(to button: UIButton, title: String) {
        var config = UIButton.Configuration.gray()
        config.title = title
        config.baseForegroundColor = .label
        config.baseBackgroundColor = V2NDesign.surface
        config.cornerStyle = .large
        config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var out = incoming
            out.font = V2NDesign.headline()
            return out
        }
        config.background.strokeColor = V2NDesign.separator
        config.background.strokeWidth = 1
        button.configuration = config
        button.accessibilityLabel = title
    }
}

// MARK: - Refined list rows

/// Note row with warm spine accent, title, subtitle and optional tags.
final class V2NNoteRowCell: UITableViewCell {
    static let reuseId = "V2NNoteRowCell"

    private let spine = UIView()
    private let titleLabel = UILabel()
    private let speakerPill = UILabel()
    private let subtitleLabel = UILabel()
    private let tagsLabel = UILabel()
    private let stack = UIStackView()
    private let metaRow = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .default
        backgroundColor = V2NDesign.surface
        accessoryType = .disclosureIndicator

        spine.translatesAutoresizingMaskIntoConstraints = false
        spine.backgroundColor = V2NDesign.spine
        spine.layer.cornerRadius = 2
        spine.layer.cornerCurve = .continuous
        contentView.addSubview(spine)

        titleLabel.font = V2NDesign.rowTitle()
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 1
        titleLabel.adjustsFontForContentSizeCategory = true

        speakerPill.font = V2NDesign.preferred(.caption2, weight: .semibold)
        speakerPill.textColor = V2NDesign.accent
        speakerPill.backgroundColor = V2NDesign.accentSoft
        speakerPill.textAlignment = .center
        speakerPill.layer.cornerRadius = V2NDesign.Radius.pill
        speakerPill.layer.cornerCurve = .continuous
        speakerPill.clipsToBounds = true
        speakerPill.setContentHuggingPriority(.required, for: .horizontal)
        speakerPill.setContentCompressionResistancePriority(.required, for: .horizontal)
        speakerPill.adjustsFontForContentSizeCategory = true
        speakerPill.isHidden = true

        subtitleLabel.font = V2NDesign.rowSubtitle()
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 2
        subtitleLabel.adjustsFontForContentSizeCategory = true

        tagsLabel.font = V2NDesign.caption()
        tagsLabel.textColor = V2NDesign.accent
        tagsLabel.numberOfLines = 1
        tagsLabel.adjustsFontForContentSizeCategory = true

        metaRow.axis = .horizontal
        metaRow.alignment = .center
        metaRow.spacing = 8
        metaRow.addArrangedSubview(speakerPill)
        metaRow.addArrangedSubview(subtitleLabel)

        stack.axis = .vertical
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(metaRow)
        stack.addArrangedSubview(tagsLabel)
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            spine.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            spine.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            spine.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            spine.widthAnchor.constraint(equalToConstant: 4),

            stack.leadingAnchor.constraint(equalTo: spine.trailingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, subtitle: String, tags: [String], speakerName: String? = nil) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle.isEmpty
        if let speakerName, !speakerName.isEmpty {
            speakerPill.isHidden = false
            speakerPill.text = "  \(speakerName)  "
        } else {
            speakerPill.isHidden = true
            speakerPill.text = nil
        }
        metaRow.isHidden = speakerPill.isHidden && subtitleLabel.isHidden
        if tags.isEmpty {
            tagsLabel.isHidden = true
            tagsLabel.text = nil
        } else {
            tagsLabel.isHidden = false
            tagsLabel.text = tags.map { "#\($0)" }.joined(separator: "  ")
        }
        accessibilityLabel = [title, speakerName, subtitle, tagsLabel.text].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ". ")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        subtitleLabel.text = nil
        subtitleLabel.isHidden = false
        speakerPill.text = nil
        speakerPill.isHidden = true
        tagsLabel.text = nil
        tagsLabel.isHidden = true
        metaRow.isHidden = false
    }
}

/// Group row with icon badge + warm surface.
final class V2NGroupRowCell: UITableViewCell {
    static let reuseId = "V2NGroupRowCell"

    private let badge = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = V2NDesign.surface
        accessoryType = .disclosureIndicator

        let badgeWrap = UIView()
        badgeWrap.translatesAutoresizingMaskIntoConstraints = false
        badgeWrap.backgroundColor = V2NDesign.accentSoft
        badgeWrap.layer.cornerRadius = V2NDesign.Radius.sm
        badgeWrap.layer.cornerCurve = .continuous
        contentView.addSubview(badgeWrap)

        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.tintColor = V2NDesign.accent
        badge.contentMode = .scaleAspectFit
        badge.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        badgeWrap.addSubview(badge)

        titleLabel.font = V2NDesign.rowTitle()
        titleLabel.textColor = .label
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.font = V2NDesign.rowSubtitle()
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 2
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(titleLabel)
        contentView.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            badgeWrap.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            badgeWrap.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            badgeWrap.widthAnchor.constraint(equalToConstant: 36),
            badgeWrap.heightAnchor.constraint(equalToConstant: 36),

            badge.centerXAnchor.constraint(equalTo: badgeWrap.centerXAnchor),
            badge.centerYAnchor.constraint(equalTo: badgeWrap.centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: badgeWrap.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ group: NativeAPIClient.GroupDTO) {
        titleLabel.text = group.name
        let visibility = group.visibility == "listed" ? String(localized: "Listado") : String(localized: "Privado")
        let pending = group.myStatus == "pending" ? String(localized: " · pedido pendente") : ""
        subtitleLabel.text = String(localized: "\(group.memberCount) membros · \(visibility)\(pending)")
        badge.image = UIImage(systemName: group.visibility == "listed" ? "globe" : "lock.fill")
        accessibilityLabel = "\(group.name). \(subtitleLabel.text ?? "")"
    }
}

// MARK: - Section header helper

final class V2NSectionHeaderLabel: UILabel {
    convenience init(text: String) {
        self.init(frame: .zero)
        self.text = text.uppercased()
        font = V2NDesign.sectionHeader()
        textColor = .secondaryLabel
        adjustsFontForContentSizeCategory = true
    }
}

extension UITableViewController {
    /// Warm canvas + grouped table tokens for insetGrouped settings / pickers.
    func v2nApplyGroupedChrome() {
        V2NChrome.styleCanvas(view)
        V2NChrome.styleGroupedTable(tableView)
        tableView.tintColor = V2NDesign.accent
        view.tintColor = V2NDesign.accent
        // Profile settings stay above the floating tab bar — keep last rows reachable (TF214).
        tableView.contentInsetAdjustmentBehavior = .automatic
    }

    /// Subclasses call `super` then this from `viewDidLayoutSubviews` when hosted in a tab.
    func v2nApplyTabBarScrollClearanceIfNeeded() {
        v2nApplyTabBarScrollClearance(to: tableView)
    }
}

extension UIListContentConfiguration {
    /// Brand fonts + accent-tinted SF Symbol (avoids default system blue).
    mutating func v2nApplyBrandListStyle(symbol: String? = nil) {
        textProperties.font = V2NDesign.preferred(.body, weight: .regular)
        textProperties.color = .label
        secondaryTextProperties.font = V2NDesign.caption()
        secondaryTextProperties.color = .secondaryLabel
        if let symbol {
            image = UIImage(systemName: symbol)
            imageProperties.tintColor = V2NDesign.accent
            imageProperties.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        } else if image != nil {
            imageProperties.tintColor = V2NDesign.accent
        }
    }
}

extension UITableViewCell {
    func v2nApplyBrandChrome() {
        tintColor = V2NDesign.accent
        backgroundColor = V2NDesign.surface
    }
}

// MARK: - Filter chips (icon-only ↔ icon + name)

struct V2NFilterChip: Equatable {
    let id: String
    let title: String
    let systemImage: String?
}

/// Shared pill row under large titles (Caderno + Ferramentas).
/// Unselected pills show only the icon; the selected pill expands to icon + name.
final class V2NFilterChipsView: UIView {
    /// Called with the newly selected id, or `nil` when the selection was cleared.
    var onSelect: ((String?) -> Void)?
    /// When true, tapping the selected pill clears selection (default / all).
    var allowsDeselect = true

    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private var chips: [V2NFilterChip] = []
    private(set) var selectedId: String?
    private var buttons: [String: UIButton] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = true
        scroll.contentInset = UIEdgeInsets(top: 0, left: V2NDesign.Space.md, bottom: 0, right: V2NDesign.Space.md)
        addSubview(scroll)

        stack.axis = .horizontal
        stack.spacing = V2NDesign.Space.xs
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 44),

            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(chips: [V2NFilterChip], selectedId: String?) {
        self.chips = chips
        self.selectedId = selectedId
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        buttons.removeAll()
        for chip in chips {
            let button = makeButton(chip: chip, selected: chip.id == selectedId)
            buttons[chip.id] = button
            stack.addArrangedSubview(button)
        }
    }

    /// Convenience for call sites that always pass a non-optional id.
    func configure(chips: [V2NFilterChip], selectedId: String) {
        configure(chips: chips, selectedId: Optional(selectedId))
    }

    func setSelected(_ id: String?, animated: Bool = true) {
        selectedId = id
        let updates = {
            for chip in self.chips {
                self.applyStyle(to: self.buttons[chip.id], chip: chip, selected: chip.id == id)
            }
            self.stack.layoutIfNeeded()
            self.scroll.layoutIfNeeded()
        }
        if animated {
            UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseInOut, .allowUserInteraction], animations: updates)
        } else {
            updates()
        }
        if let id, let button = buttons[id] {
            scroll.scrollRectToVisible(button.frame.insetBy(dx: -24, dy: 0), animated: animated)
        }
    }

    private func makeButton(chip: V2NFilterChip, selected: Bool) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tag = chips.firstIndex(where: { $0.id == chip.id }) ?? 0
        button.accessibilityLabel = chip.title
        button.addTarget(self, action: #selector(tap(_:)), for: .touchUpInside)
        button.heightAnchor.constraint(equalToConstant: 34).isActive = true
        // Floor width so icon-only pills stay clearly capsule-shaped (~2× icon width).
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 72).isActive = true
        applyStyle(to: button, chip: chip, selected: selected)
        return button
    }

    private func applyStyle(to button: UIButton?, chip: V2NFilterChip, selected: Bool) {
        guard let button else { return }
        var config = UIButton.Configuration.filled()
        // Selected → icon + name; unselected → icon only (title stays for VoiceOver).
        config.title = selected ? chip.title : nil
        if let systemImage = chip.systemImage {
            config.image = UIImage(systemName: systemImage)
            config.imagePadding = selected ? 6 : 0
            config.imagePlacement = .leading
        }
        config.cornerStyle = .capsule
        // Unselected icon-only pills need generous horizontal inset so they read as
        // capsules (wider than tall — roughly 2× the icon), not near-circles.
        let horizontal: CGFloat = selected ? 16 : 24
        config.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: horizontal, bottom: 7, trailing: horizontal)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var out = incoming
            out.font = V2NDesign.preferred(.subheadline, weight: .semibold)
            return out
        }
        if selected {
            config.baseBackgroundColor = V2NDesign.accent
            config.baseForegroundColor = .white
        } else {
            config.baseBackgroundColor = UIColor { traits in
                if traits.userInterfaceStyle == .dark {
                    return UIColor(white: 1, alpha: 0.12)
                }
                return UIColor(white: 0, alpha: 0.08)
            }
            config.baseForegroundColor = .label
        }
        button.configuration = config
        button.accessibilityLabel = chip.title
        button.accessibilityTraits = selected ? [.button, .selected] : .button
    }

    @objc private func tap(_ sender: UIButton) {
        guard sender.tag >= 0, sender.tag < chips.count else { return }
        let chip = chips[sender.tag]
        let next: String?
        if chip.id == selectedId, allowsDeselect {
            next = nil
        } else {
            next = chip.id
        }
        setSelected(next, animated: true)
        V2NHaptics.selection()
        onSelect?(next)
    }
}

// MARK: - Segmented mode toggle (Siglas / Nomes)

final class V2NModeToggle: UIView {
    var onChange: ((Bool) -> Void)?
    /// When true → compact abbreviations.
    private(set) var isCompact = false
    private let compactButton = UIButton(type: .system)
    private let namesButton = UIButton(type: .system)
    private let wrap = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        wrap.translatesAutoresizingMaskIntoConstraints = false
        wrap.backgroundColor = V2NDesign.surface
        wrap.layer.cornerRadius = V2NDesign.Radius.pill
        wrap.layer.cornerCurve = .continuous
        wrap.layer.borderWidth = 0.5
        wrap.layer.borderColor = V2NDesign.separator.cgColor
        addSubview(wrap)

        for (button, title) in [(compactButton, String(localized: "Siglas")), (namesButton, String(localized: "Nomes"))] {
            button.translatesAutoresizingMaskIntoConstraints = false
            var config = UIButton.Configuration.plain()
            config.title = title
            config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var out = incoming
                out.font = V2NDesign.preferred(.footnote, weight: .semibold)
                return out
            }
            button.configuration = config
            button.layer.cornerRadius = V2NDesign.Radius.pill
            button.layer.cornerCurve = .continuous
            button.clipsToBounds = true
            wrap.addSubview(button)
        }
        compactButton.addTarget(self, action: #selector(tapCompact), for: .touchUpInside)
        namesButton.addTarget(self, action: #selector(tapNames), for: .touchUpInside)
        compactButton.accessibilityLabel = String(localized: "Siglas")
        namesButton.accessibilityLabel = String(localized: "Nomes")

        NSLayoutConstraint.activate([
            wrap.topAnchor.constraint(equalTo: topAnchor),
            wrap.trailingAnchor.constraint(equalTo: trailingAnchor),
            wrap.bottomAnchor.constraint(equalTo: bottomAnchor),
            wrap.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            heightAnchor.constraint(equalToConstant: 34),

            compactButton.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 3),
            compactButton.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 3),
            compactButton.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -3),

            namesButton.leadingAnchor.constraint(equalTo: compactButton.trailingAnchor, constant: 2),
            namesButton.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -3),
            namesButton.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 3),
            namesButton.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -3),
        ])
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setCompact(_ compact: Bool) {
        isCompact = compact
        refresh()
    }

    private func refresh() {
        style(compactButton, selected: isCompact)
        style(namesButton, selected: !isCompact)
        compactButton.accessibilityTraits = isCompact ? [.button, .selected] : .button
        namesButton.accessibilityTraits = !isCompact ? [.button, .selected] : .button
    }

    private func style(_ button: UIButton, selected: Bool) {
        var config = button.configuration ?? .plain()
        config.baseForegroundColor = selected ? .white : .secondaryLabel
        config.background.backgroundColor = selected ? V2NDesign.accent : .clear
        button.configuration = config
    }

    @objc private func tapCompact() {
        let changed = !isCompact
        isCompact = true
        refresh()
        if changed { V2NHaptics.selection() }
        // Always notify so the parent can resync layout if selection and content drifted.
        onChange?(true)
    }

    @objc private func tapNames() {
        let changed = isCompact
        isCompact = false
        refresh()
        if changed { V2NHaptics.selection() }
        onChange?(false)
    }
}

// MARK: - Shared Bible book grid cells (Versículos + note “Add reference”)

/// Abbreviation square used by Versículos (Siglas) and the note bible-ref insert picker.
final class V2NBookAbbrCell: UICollectionViewCell {
    static let reuseId = "V2NBookAbbrCell"
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = V2NDesign.surface
        contentView.layer.cornerRadius = V2NDesign.Radius.sm
        contentView.layer.cornerCurve = .continuous
        contentView.layer.borderWidth = 0.5
        contentView.layer.borderColor = V2NDesign.separator.cgColor

        label.font = V2NDesign.preferred(.footnote, weight: .semibold)
        label.textColor = .label
        label.textAlignment = .center
        label.adjustsFontForContentSizeCategory = true
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -2),
        ])
        isAccessibilityElement = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(abbr: String, accessibilityName: String) {
        label.text = abbr
        accessibilityLabel = accessibilityName
    }
}

/// Name + abbr row cell used by Versículos (Nomes mode).
final class V2NBookNameCell: UICollectionViewCell {
    static let reuseId = "V2NBookNameCell"
    private let nameLabel = UILabel()
    private let abbrLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = V2NDesign.surface
        contentView.layer.cornerRadius = V2NDesign.Radius.sm
        contentView.layer.cornerCurve = .continuous
        contentView.layer.borderWidth = 0.5
        contentView.layer.borderColor = V2NDesign.separator.cgColor

        nameLabel.font = V2NDesign.preferred(.subheadline, weight: .medium)
        nameLabel.textColor = .label
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        abbrLabel.font = V2NDesign.caption()
        abbrLabel.textColor = .secondaryLabel
        abbrLabel.setContentHuggingPriority(.required, for: .horizontal)
        abbrLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(nameLabel)
        contentView.addSubview(abbrLabel)
        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            nameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            abbrLabel.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 6),
            abbrLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            abbrLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
        isAccessibilityElement = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(name: String, abbr: String) {
        nameLabel.text = name
        abbrLabel.text = abbr
        accessibilityLabel = "\(name), \(abbr)"
    }
}

final class V2NBookSectionHeaderView: UICollectionReusableView {
    static let reuseId = "V2NBookSectionHeaderView"
    private let label = UILabel()
    private let trailingHost = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = V2NDesign.sectionHeader()
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        trailingHost.translatesAutoresizingMaskIntoConstraints = false
        trailingHost.setContentHuggingPriority(.required, for: .horizontal)
        trailingHost.setContentCompressionResistancePriority(.required, for: .horizontal)

        addSubview(label)
        addSubview(trailingHost)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingHost.leadingAnchor, constant: -8),

            trailingHost.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            trailingHost.centerYAnchor.constraint(equalTo: centerYAnchor),
            trailingHost.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            trailingHost.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// `trailing` is typically the Siglas/Nomes toggle on the Old Testament header row.
    func configure(title: String, trailing: UIView? = nil) {
        label.text = title.uppercased()
        for sub in trailingHost.subviews {
            sub.removeFromSuperview()
        }
        guard let trailing else { return }
        trailing.translatesAutoresizingMaskIntoConstraints = false
        trailingHost.addSubview(trailing)
        NSLayoutConstraint.activate([
            trailing.leadingAnchor.constraint(equalTo: trailingHost.leadingAnchor),
            trailing.trailingAnchor.constraint(equalTo: trailingHost.trailingAnchor),
            trailing.topAnchor.constraint(equalTo: trailingHost.topAnchor),
            trailing.bottomAnchor.constraint(equalTo: trailingHost.bottomAnchor),
        ])
    }
}

enum V2NBookGridLayout {
    /// Compositional layout matching Versículos Siglas/Nomes grids.
    /// Pass a provider so Siglas/Nomes toggles can `invalidateLayout()` without rebuilding.
    static func make(isCompact: @escaping () -> Bool) -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { sectionIndex, env in
            let compact = isCompact()
            let width = env.container.effectiveContentSize.width
            let columns = max(1, Int(compact ? (width > 500 ? 8 : 5) : 2))
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1 / CGFloat(columns)),
                heightDimension: .absolute(compact ? 52 : 56)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            item.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .absolute(compact ? 52 : 56)
            )
            // `repeatingSubitem:` needs iOS 16+; deployment target is 15.0.
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: groupSize,
                subitem: item,
                count: columns
            )
            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 12, bottom: 12, trailing: 12)
            // Taller OT header so Siglas/Nomes can sit on the same row inside the scroll view.
            let headerHeight: CGFloat = sectionIndex == 0 ? 44 : 32
            let header = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(headerHeight)),
                elementKind: UICollectionView.elementKindSectionHeader,
                alignment: .top
            )
            section.boundarySupplementaryItems = [header]
            return section
        }
    }

    static func make(compact: Bool) -> UICollectionViewCompositionalLayout {
        make(isCompact: { compact })
    }
}

// MARK: - Number grid (chapter / verse pickers)

enum V2NNumberGridLayout {
    static func make(columns: Int = 5) -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { _, env in
            let width = env.container.effectiveContentSize.width
            let cols = max(4, width > 500 ? min(10, columns + 3) : columns)
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1 / CGFloat(cols)),
                heightDimension: .absolute(48)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            item.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .absolute(48)
            )
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: groupSize,
                subitem: item,
                count: cols
            )
            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 16, trailing: 12)
            return section
        }
    }
}

final class V2NNumberCell: UICollectionViewCell {
    static let reuseId = "V2NNumberCell"
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = V2NDesign.Radius.sm
        contentView.layer.cornerCurve = .continuous
        contentView.layer.borderWidth = 0.5
        contentView.layer.borderColor = V2NDesign.separator.cgColor

        label.font = V2NDesign.preferred(.subheadline, weight: .semibold)
        label.textAlignment = .center
        label.adjustsFontForContentSizeCategory = true
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
        apply(style: .plain)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    enum Style { case plain, edge, inRange }

    func configure(number: Int, style: Style) {
        label.text = "\(number)"
        accessibilityLabel = "\(number)"
        apply(style: style)
    }

    private func apply(style: Style) {
        switch style {
        case .plain:
            contentView.backgroundColor = V2NDesign.surface
            label.textColor = .label
            contentView.layer.borderWidth = 0.5
        case .edge:
            contentView.backgroundColor = V2NDesign.accent
            label.textColor = .white
            contentView.layer.borderWidth = 0
        case .inRange:
            contentView.backgroundColor = V2NDesign.accentSoft
            label.textColor = .label
            contentView.layer.borderWidth = 0
        }
    }
}

// MARK: - Tools home cards

final class V2NToolCardCell: UICollectionViewCell {
    static let reuseId = "V2NToolCardCell"
    private let card = UIView()
    private let iconWrap = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = V2NDesign.surface
        card.layer.cornerRadius = V2NDesign.Radius.lg
        card.layer.cornerCurve = .continuous
        V2NDesign.applyCardShadow(to: card.layer)
        contentView.addSubview(card)

        iconWrap.translatesAutoresizingMaskIntoConstraints = false
        iconWrap.backgroundColor = V2NDesign.accentSoft
        iconWrap.layer.cornerRadius = V2NDesign.Radius.md
        iconWrap.layer.cornerCurve = .continuous
        card.addSubview(iconWrap)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = V2NDesign.accent
        iconWrap.addSubview(iconView)

        titleLabel.font = V2NDesign.preferred(.headline, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.font = V2NDesign.caption()
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 2
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(titleLabel)
        card.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            iconWrap.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            iconWrap.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            iconWrap.widthAnchor.constraint(equalToConstant: 44),
            iconWrap.heightAnchor.constraint(equalToConstant: 44),

            iconView.centerXAnchor.constraint(equalTo: iconWrap.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconWrap.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),

            titleLabel.topAnchor.constraint(equalTo: iconWrap.bottomAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            subtitleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            subtitleLabel.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -16),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, subtitle: String, systemImage: String) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        iconView.image = UIImage(systemName: systemImage)
        accessibilityLabel = "\(title). \(subtitle)"
    }
}

// MARK: - Bible app logo tile

final class V2NBibleAppLogoCell: UICollectionViewCell {
    static let reuseId = "V2NBibleAppLogoCell"
    private let logo = UIImageView()
    private let nameLabel = UILabel()
    private let ring = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = V2NDesign.surface
        contentView.layer.cornerRadius = V2NDesign.Radius.md
        contentView.layer.cornerCurve = .continuous
        contentView.layer.borderWidth = 1
        contentView.layer.borderColor = V2NDesign.separator.cgColor

        ring.translatesAutoresizingMaskIntoConstraints = false
        ring.backgroundColor = .clear
        ring.layer.cornerRadius = 14
        ring.layer.cornerCurve = .continuous
        ring.clipsToBounds = true
        contentView.addSubview(ring)

        logo.translatesAutoresizingMaskIntoConstraints = false
        logo.contentMode = .scaleAspectFill
        logo.clipsToBounds = true
        logo.layer.cornerRadius = 12
        logo.layer.cornerCurve = .continuous
        ring.addSubview(logo)

        nameLabel.font = V2NDesign.caption()
        nameLabel.textColor = .secondaryLabel
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 2
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(nameLabel)

        NSLayoutConstraint.activate([
            ring.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            ring.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            ring.widthAnchor.constraint(equalToConstant: 56),
            ring.heightAnchor.constraint(equalToConstant: 56),

            logo.centerXAnchor.constraint(equalTo: ring.centerXAnchor),
            logo.centerYAnchor.constraint(equalTo: ring.centerYAnchor),
            logo.widthAnchor.constraint(equalToConstant: 52),
            logo.heightAnchor.constraint(equalToConstant: 52),

            nameLabel.topAnchor.constraint(equalTo: ring.bottomAnchor, constant: 8),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),
            nameLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -8),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(name: String, image: UIImage?, selected: Bool) {
        nameLabel.text = name
        logo.image = image
        accessibilityLabel = name
        accessibilityTraits = selected ? [.button, .selected] : .button
        if selected {
            contentView.layer.borderWidth = 2
            contentView.layer.borderColor = V2NDesign.accent.cgColor
            contentView.backgroundColor = V2NDesign.accentSoft
            nameLabel.textColor = V2NDesign.accent
            nameLabel.font = V2NDesign.preferred(.caption1, weight: .semibold)
        } else {
            contentView.layer.borderWidth = 1
            contentView.layer.borderColor = V2NDesign.separator.cgColor
            contentView.backgroundColor = V2NDesign.surface
            nameLabel.textColor = .secondaryLabel
            nameLabel.font = V2NDesign.caption()
        }
    }
}

// MARK: - Branded create-name form (Lists / Themes — no system-blue alerts)

/// Polished form sheet for naming a new list or theme. Replaces default UIAlertController create flows.
final class V2NNamedCreateViewController: UIViewController, UITextFieldDelegate {
    enum Kind {
        case list
        case theme

        var title: String {
            switch self {
            case .list: return String(localized: "Nova lista")
            case .theme: return String(localized: "Novo tema")
            }
        }

        var placeholder: String {
            switch self {
            case .list: return String(localized: "Nome da lista")
            case .theme: return String(localized: "Nome do tema")
            }
        }

        var lead: String {
            switch self {
            case .list: return String(localized: "Dê um nome curto para a sua lista de versículos.")
            case .theme: return String(localized: "Dê um nome curto para o seu tema pessoal.")
            }
        }

        var confirmTitle: String {
            switch self {
            case .list: return String(localized: "Criar lista")
            case .theme: return String(localized: "Criar tema")
            }
        }

        var symbol: String {
            switch self {
            case .list: return "bookmark.fill"
            case .theme: return "tag.fill"
            }
        }
    }

    private let kind: Kind
    private let onConfirm: (String) -> Void
    private let nameField = UITextField()
    private let confirmButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private var busy = false

    init(kind: Kind, onConfirm: @escaping (String) -> Void) {
        self.kind = kind
        self.onConfirm = onConfirm
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        V2NChrome.styleCanvas(view)
        title = kind.title
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: String(localized: "Cancelar"),
            style: .plain,
            target: self,
            action: #selector(cancel)
        )

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        scroll.keyboardDismissMode = .interactive
        view.addSubview(scroll)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = V2NDesign.Space.md
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        let iconWrap = UIView()
        iconWrap.translatesAutoresizingMaskIntoConstraints = false
        iconWrap.backgroundColor = V2NDesign.accentSoft
        iconWrap.layer.cornerRadius = V2NDesign.Radius.lg
        iconWrap.layer.cornerCurve = .continuous

        let icon = UIImageView(image: UIImage(systemName: kind.symbol))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = V2NDesign.accent
        icon.contentMode = .scaleAspectFit
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
        iconWrap.addSubview(icon)

        let lead = UILabel()
        lead.text = kind.lead
        lead.font = V2NDesign.rowSubtitle()
        lead.textColor = .secondaryLabel
        lead.numberOfLines = 0
        lead.adjustsFontForContentSizeCategory = true

        styleField(nameField, placeholder: kind.placeholder)
        nameField.delegate = self
        nameField.returnKeyType = .done
        nameField.addTarget(self, action: #selector(nameChanged), for: .editingChanged)
        nameField.becomeFirstResponder()

        V2NButtonStyle.applyPrimary(to: confirmButton, title: kind.confirmTitle)
        confirmButton.addTarget(self, action: #selector(confirm), for: .touchUpInside)
        confirmButton.isEnabled = false
        confirmButton.alpha = 0.45

        statusLabel.font = V2NDesign.caption()
        statusLabel.textColor = V2NDesign.danger
        statusLabel.numberOfLines = 0
        statusLabel.isHidden = true

        let iconRow = UIView()
        iconRow.translatesAutoresizingMaskIntoConstraints = false
        iconRow.addSubview(iconWrap)
        NSLayoutConstraint.activate([
            iconWrap.leadingAnchor.constraint(equalTo: iconRow.leadingAnchor),
            iconWrap.topAnchor.constraint(equalTo: iconRow.topAnchor),
            iconWrap.bottomAnchor.constraint(equalTo: iconRow.bottomAnchor),
            iconWrap.widthAnchor.constraint(equalToConstant: 64),
            iconWrap.heightAnchor.constraint(equalToConstant: 64),
            icon.centerXAnchor.constraint(equalTo: iconWrap.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconWrap.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 30),
            icon.heightAnchor.constraint(equalToConstant: 30),
        ])

        stack.addArrangedSubview(iconRow)
        stack.addArrangedSubview(lead)
        stack.addArrangedSubview(nameField)
        stack.addArrangedSubview(confirmButton)
        stack.addArrangedSubview(statusLabel)
        stack.setCustomSpacing(V2NDesign.Space.lg, after: lead)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: V2NDesign.Space.lg),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: V2NDesign.Space.lg),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -V2NDesign.Space.lg),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -V2NDesign.Space.xl),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -V2NDesign.Space.lg * 2),

            nameField.heightAnchor.constraint(equalToConstant: 52),
        ])
    }

    private func styleField(_ field: UITextField, placeholder: String) {
        field.placeholder = placeholder
        field.borderStyle = .none
        field.backgroundColor = V2NDesign.surface
        field.layer.cornerRadius = V2NDesign.Radius.md
        field.layer.cornerCurve = .continuous
        field.layer.borderWidth = 1
        field.layer.borderColor = V2NDesign.separator.cgColor
        field.font = V2NDesign.body()
        field.tintColor = V2NDesign.accent
        field.clearButtonMode = .whileEditing
        field.autocapitalizationType = .sentences
        field.returnKeyType = .done
        let pad = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
        field.leftView = pad
        field.leftViewMode = .always
        field.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
        field.rightViewMode = .always
        field.accessibilityLabel = placeholder
    }

    @objc private func nameChanged() {
        let ok = !(nameField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        confirmButton.isEnabled = ok && !busy
        confirmButton.alpha = ok && !busy ? 1 : 0.45
        statusLabel.isHidden = true
    }

    @objc private func cancel() {
        dismiss(animated: true)
    }

    @objc private func confirm() {
        let name = (nameField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !busy else { return }
        busy = true
        confirmButton.isEnabled = false
        confirmButton.alpha = 0.45
        nameField.resignFirstResponder()
        onConfirm(name)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        confirm()
        return true
    }

    func presentFailure(_ message: String) {
        busy = false
        nameChanged()
        statusLabel.text = message
        statusLabel.isHidden = false
    }

    func finishSuccess() {
        dismiss(animated: true)
    }
}
