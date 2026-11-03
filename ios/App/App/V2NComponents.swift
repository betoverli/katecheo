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

    func showLoading(message: String = "Carregando…") {
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
        let visibility = group.visibility == "listed" ? "Listado" : "Privado"
        let pending = group.myStatus == "pending" ? " · pedido pendente" : ""
        subtitleLabel.text = "\(group.memberCount) membros · \(visibility)\(pending)"
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
