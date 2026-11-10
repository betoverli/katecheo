import UIKit

/// Native Notification Center — paged inbox with day grouping, mark-read, and deep-link open.
final class NotificationsCenterViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let refresh = UIRefreshControl()
    private let emptyState = V2NEmptyStateView()
    private let viewModel = NotificationsCenterViewModel()
    private var markAllButton: UIBarButtonItem?

    /// Test hook — drives the same VM the UI uses.
    var testing_viewModel: NotificationsCenterViewModel { viewModel }
    var testing_tableView: UITableView { tableView }

    override func viewDidLoad() {
        super.viewDidLoad()
        V2NChrome.styleScreen(view)
        title = String(localized: "Avisos")
        navigationItem.largeTitleDisplayMode = .never
        if let nav = navigationController {
            V2NChrome.style(navigationController: nav)
        }

        let markAll = UIBarButtonItem(
            title: String(localized: "Marcar todas como lidas"),
            style: .plain,
            target: self,
            action: #selector(markAllTapped)
        )
        markAll.accessibilityLabel = String(localized: "Marcar todas como lidas")
        markAllButton = markAll
        navigationItem.rightBarButtonItem = markAll

        tableView.translatesAutoresizingMaskIntoConstraints = false
        V2NChrome.styleGroupedTable(tableView)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(NotificationsCenterRowCell.self, forCellReuseIdentifier: NotificationsCenterRowCell.reuseId)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 88
        refresh.addTarget(self, action: #selector(pullRefresh), for: .valueChanged)
        tableView.refreshControl = refresh

        view.addSubview(tableView)
        view.addSubview(emptyState)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyState.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            emptyState.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyState.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyState.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])

        viewModel.onChange = { [weak self] in
            self?.render()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task { await viewModel.loadInitial(force: true) }
    }

    @objc private func pullRefresh() {
        Task {
            await viewModel.loadInitial(force: true)
            await MainActor.run { refresh.endRefreshing() }
        }
    }

    @objc private func markAllTapped() {
        V2NHaptics.light()
        Task {
            _ = await viewModel.markAllRead()
        }
    }

    private func render() {
        tableView.reloadData()
        markAllButton?.isEnabled = viewModel.hasUnread
        markAllButton?.tintColor = viewModel.hasUnread ? V2NDesign.accent : .tertiaryLabel

        if viewModel.isLoading && viewModel.items.isEmpty {
            emptyState.showLoading(message: String(localized: "Carregando…"))
            tableView.isHidden = true
            return
        }

        if viewModel.showsError {
            emptyState.show(
                symbol: "exclamationmark.triangle",
                title: String(localized: "Erro"),
                message: viewModel.errorMessage ?? String(localized: "Não foi possível carregar os avisos."),
                actionTitle: String(localized: "Tentar de novo"),
                action: { [weak self] in
                    Task { await self?.viewModel.loadInitial(force: true) }
                }
            )
            tableView.isHidden = true
            return
        }

        if viewModel.showsEmpty {
            emptyState.show(
                symbol: "bell.slash",
                title: String(localized: "Nenhum aviso ainda"),
                message: String(localized: "Quando alguém compartilhar uma nota, convidar para um grupo ou lembrar da leitura, o aviso aparece aqui.")
            )
            tableView.isHidden = true
            return
        }

        emptyState.hide()
        tableView.isHidden = false
    }

    // MARK: - Table

    func numberOfSections(in tableView: UITableView) -> Int {
        viewModel.sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.sections[section].items.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        viewModel.sections[section].title
    }

    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        guard let header = view as? UITableViewHeaderFooterView else { return }
        header.textLabel?.font = V2NDesign.sectionHeader()
        header.textLabel?.textColor = .secondaryLabel
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: NotificationsCenterRowCell.reuseId,
            for: indexPath
        ) as! NotificationsCenterRowCell
        let item = viewModel.sections[indexPath.section].items[indexPath.row]
        cell.configure(item)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = viewModel.sections[indexPath.section].items[indexPath.row]
        V2NHaptics.selection()
        Task {
            if !item.read {
                _ = await viewModel.markRead(id: item.id)
            }
            await MainActor.run {
                NativeDeepLinkRouter.open(href: item.href)
            }
        }
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let item = viewModel.sections[indexPath.section].items[indexPath.row]
        guard !item.read else { return nil }
        let action = UIContextualAction.v2nIconOnly(
            style: .normal,
            systemName: "checkmark.circle",
            accessibilityLabel: String(localized: "Marcar como lida"),
            backgroundColor: V2NDesign.accent
        ) { [weak self] _, _, completion in
            Task {
                _ = await self?.viewModel.markRead(id: item.id)
                await MainActor.run { completion(true) }
            }
        }
        let config = UISwipeActionsConfiguration(actions: [action])
        config.performsFirstActionWithFullSwipe = true
        return config
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        // Map section/row → flat index for pagination threshold.
        var flat = 0
        for section in 0..<indexPath.section {
            flat += viewModel.sections[section].items.count
        }
        flat += indexPath.row
        Task { await viewModel.loadMoreIfNeeded(currentIndex: flat) }
    }
}

// MARK: - Row cell

private final class NotificationsCenterRowCell: UITableViewCell {
    static let reuseId = "notifications-center-row"

    private let iconWrap = UIView()
    private let iconView = UIImageView()
    private let unreadDot = UIView()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let timeLabel = UILabel()
    private let textStack = UIStackView()
    private let titleRow = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .default
        backgroundColor = V2NDesign.surface
        selectedBackgroundView = {
            let view = UIView()
            view.backgroundColor = V2NDesign.accentSoft
            return view
        }()

        iconWrap.translatesAutoresizingMaskIntoConstraints = false
        iconWrap.backgroundColor = V2NDesign.accentSoft
        iconWrap.layer.cornerRadius = V2NDesign.Radius.md
        iconWrap.layer.cornerCurve = .continuous

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = V2NDesign.accent
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        iconWrap.addSubview(iconView)

        unreadDot.translatesAutoresizingMaskIntoConstraints = false
        unreadDot.backgroundColor = V2NDesign.accent
        unreadDot.layer.cornerRadius = 4
        unreadDot.isHidden = true

        titleLabel.font = V2NDesign.rowTitle()
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 2
        titleLabel.adjustsFontForContentSizeCategory = true

        bodyLabel.font = V2NDesign.rowSubtitle()
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.numberOfLines = 3
        bodyLabel.adjustsFontForContentSizeCategory = true

        timeLabel.font = V2NDesign.caption()
        timeLabel.textColor = .tertiaryLabel
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        timeLabel.adjustsFontForContentSizeCategory = true

        titleRow.axis = .horizontal
        titleRow.alignment = .firstBaseline
        titleRow.spacing = V2NDesign.Space.sm
        titleRow.addArrangedSubview(titleLabel)
        titleRow.addArrangedSubview(timeLabel)

        textStack.axis = .vertical
        textStack.alignment = .fill
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.addArrangedSubview(titleRow)
        textStack.addArrangedSubview(bodyLabel)

        contentView.addSubview(iconWrap)
        contentView.addSubview(unreadDot)
        contentView.addSubview(textStack)

        NSLayoutConstraint.activate([
            iconWrap.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: V2NDesign.Space.md),
            iconWrap.topAnchor.constraint(equalTo: contentView.topAnchor, constant: V2NDesign.Space.md),
            iconWrap.widthAnchor.constraint(equalToConstant: 36),
            iconWrap.heightAnchor.constraint(equalToConstant: 36),

            iconView.centerXAnchor.constraint(equalTo: iconWrap.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconWrap.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            unreadDot.leadingAnchor.constraint(equalTo: iconWrap.trailingAnchor, constant: V2NDesign.Space.sm),
            unreadDot.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            unreadDot.widthAnchor.constraint(equalToConstant: 8),
            unreadDot.heightAnchor.constraint(equalToConstant: 8),

            textStack.leadingAnchor.constraint(equalTo: unreadDot.trailingAnchor, constant: V2NDesign.Space.sm),
            textStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -V2NDesign.Space.md),
            textStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: V2NDesign.Space.md),
            textStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -V2NDesign.Space.md),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ item: NativeAPIClient.InboxItemDTO) {
        iconView.image = UIImage(systemName: NotificationsCenterViewModel.symbolName(forKind: item.kind))
        titleLabel.text = item.title
        bodyLabel.text = item.body
        bodyLabel.isHidden = item.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        timeLabel.text = NotificationsCenterViewModel.relativeTime(from: item.createdAt)

        let unread = !item.read
        unreadDot.isHidden = !unread
        backgroundColor = unread ? V2NDesign.accentSoft : V2NDesign.surface
        titleLabel.font = unread
            ? V2NDesign.preferred(.body, weight: .semibold)
            : V2NDesign.preferred(.body, weight: .regular)

        accessibilityLabel = [item.title, item.body, timeLabel.text]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
        accessibilityValue = unread ? String(localized: "Não lido") : nil
    }
}
