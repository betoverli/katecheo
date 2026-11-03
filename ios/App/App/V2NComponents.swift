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
    private let subtitleLabel = UILabel()
    private let tagsLabel = UILabel()
    private let stack = UIStackView()

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

        subtitleLabel.font = V2NDesign.rowSubtitle()
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 2
        subtitleLabel.adjustsFontForContentSizeCategory = true

        tagsLabel.font = V2NDesign.caption()
        tagsLabel.textColor = V2NDesign.accent
        tagsLabel.numberOfLines = 1
        tagsLabel.adjustsFontForContentSizeCategory = true

        stack.axis = .vertical
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(subtitleLabel)
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

    func configure(title: String, subtitle: String, tags: [String]) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        if tags.isEmpty {
            tagsLabel.isHidden = true
            tagsLabel.text = nil
        } else {
            tagsLabel.isHidden = false
            tagsLabel.text = tags.map { "#\($0)" }.joined(separator: "  ")
        }
        accessibilityLabel = [title, subtitle, tagsLabel.text].compactMap { $0 }.joined(separator: ". ")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        subtitleLabel.text = nil
        tagsLabel.text = nil
        tagsLabel.isHidden = true
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
    }
}

// MARK: - Filter chips (WhatsApp-style)

struct V2NFilterChip: Equatable {
    let id: String
    let title: String
    let systemImage: String?
}

/// Horizontal scrolling pill chips under a large title.
final class V2NFilterChipsView: UIView {
    var onSelect: ((String) -> Void)?

    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private var chips: [V2NFilterChip] = []
    private var selectedId: String = ""
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

    func configure(chips: [V2NFilterChip], selectedId: String) {
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

    func setSelected(_ id: String) {
        selectedId = id
        for chip in chips {
            applyStyle(to: buttons[chip.id], selected: chip.id == id)
        }
    }

    private func makeButton(chip: V2NFilterChip, selected: Bool) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tag = chips.firstIndex(where: { $0.id == chip.id }) ?? 0
        button.accessibilityLabel = chip.title
        button.addTarget(self, action: #selector(tap(_:)), for: .touchUpInside)
        button.heightAnchor.constraint(equalToConstant: 34).isActive = true
        applyStyle(to: button, selected: selected, title: chip.title, systemImage: chip.systemImage)
        return button
    }

    private func applyStyle(to button: UIButton?, selected: Bool, title: String? = nil, systemImage: String? = nil) {
        guard let button else { return }
        var config = UIButton.Configuration.filled()
        if let title {
            config.title = title
        } else if let existing = button.configuration?.title {
            config.title = existing
        }
        if let systemImage {
            config.image = UIImage(systemName: systemImage)
            config.imagePadding = 6
            config.imagePlacement = .leading
        } else if let existing = button.configuration?.image {
            config.image = existing
            config.imagePadding = 6
        }
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 14, bottom: 7, trailing: 14)
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
    }

    @objc private func tap(_ sender: UIButton) {
        guard sender.tag >= 0, sender.tag < chips.count else { return }
        let chip = chips[sender.tag]
        setSelected(chip.id)
        V2NHaptics.selection()
        onSelect?(chip.id)
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

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = V2NDesign.sectionHeader()
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String) {
        label.text = title.uppercased()
    }
}

enum V2NBookGridLayout {
    /// Compositional layout matching Versículos Siglas/Nomes grids.
    /// Pass a provider so Siglas/Nomes toggles can `invalidateLayout()` without rebuilding.
    static func make(isCompact: @escaping () -> Bool) -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { _, env in
            let compact = isCompact()
            let columns: CGFloat = compact ? (env.container.effectiveContentSize.width > 500 ? 8 : 5) : 2
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1 / columns),
                heightDimension: .absolute(compact ? 52 : 56)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            item.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .absolute(compact ? 52 : 56)
            )
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 12, bottom: 12, trailing: 12)
            let header = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(32)),
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
