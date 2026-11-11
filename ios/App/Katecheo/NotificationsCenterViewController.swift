import UIKit

/// Native Notification Center — paged inbox with day grouping, mark-read, and deep-link open.
final class NotificationsCenterViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let refresh = UIRefreshControl()
    private let emptyState = KCEmptyStateView()
    private let viewModel = NotificationsCenterViewModel()
    private var markAllButton: UIBarButtonItem?
    private var clearAllButton: UIBarButtonItem?

    /// Test hook — drives the same VM the UI uses.
    var testing_viewModel: NotificationsCenterViewModel { viewModel }
    var testing_tableView: UITableView { tableView }
    var testing_markAllButton: UIBarButtonItem? { markAllButton }
    var testing_clearAllButton: UIBarButtonItem? { clearAllButton }

    override func viewDidLoad() {
        super.viewDidLoad()
        KCChrome.styleScreen(view)
        title = String(localized: "Avisos")
        navigationItem.largeTitleDisplayMode = .never
        if let nav = navigationController {
            KCChrome.style(navigationController: nav)
        }

        let markAll = UIBarButtonItem(
            title: String(localized: "Marcar todas como lidas"),
            style: .plain,
            target: self,
            action: #selector(markAllTapped)
        )
        markAll.accessibilityLabel = String(localized: "Marcar todas como lidas")
        markAllButton = markAll

        let clearAll = UIBarButtonItem(
            title: String(localized: "Limpar tudo"),
            style: .plain,
            target: self,
            action: #selector(clearAllTapped)
        )
        clearAll.accessibilityLabel = String(localized: "Limpar tudo")
        clearAll.tintColor = KCDesign.danger
        clearAllButton = clearAll

        // rightBarButtonItems[0] is trailing-most — keep Mark all as the primary action.
        navigationItem.rightBarButtonItems = [markAll, clearAll]

        tableView.translatesAutoresizingMaskIntoConstraints = false
        KCChrome.styleGroupedTable(tableView)
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
        KCHaptics.light()
        Task {
            _ = await viewModel.markAllRead()
        }
    }

    @objc private func clearAllTapped() {
        guard !viewModel.items.isEmpty else { return }
        KCHaptics.light()
        let sheet = UIAlertController(
            title: String(localized: "Limpar todos os avisos?"),
            message: String(localized: "Isso remove os avisos da lista. Pedidos de amizade continuam em Amigos."),
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: String(localized: "Limpar tudo"), style: .destructive) { [weak self] _ in
            Task {
                _ = await self?.viewModel.clearAll()
            }
        })
        sheet.addAction(UIAlertAction(title: String(localized: "Cancelar"), style: .cancel))
        KCConfirmation.presentActionSheet(
            sheet,
            from: self,
            barButtonItem: clearAllButton
        )
    }

    private func render() {
        tableView.reloadData()
        markAllButton?.isEnabled = viewModel.hasUnread
        markAllButton?.tintColor = viewModel.hasUnread ? KCDesign.accent : .tertiaryLabel
        let hasItems = !viewModel.items.isEmpty
        clearAllButton?.isEnabled = hasItems
        clearAllButton?.tintColor = hasItems ? KCDesign.danger : .tertiaryLabel

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
        header.textLabel?.font = KCDesign.sectionHeader()
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
        KCHaptics.selection()
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
        var actions: [UIContextualAction] = []

        let delete = UIContextualAction.kcIconOnly(
            style: .destructive,
            systemName: "trash",
            accessibilityLabel: String(localized: "Excluir")
        ) { [weak self] _, _, completion in
            Task {
                let ok = await self?.viewModel.deleteNotification(id: item.id) ?? false
                await MainActor.run { completion(ok) }
            }
        }
        actions.append(delete)

        if !item.read {
            let markRead = UIContextualAction.kcIconOnly(
                style: .normal,
                systemName: "checkmark.circle",
                accessibilityLabel: String(localized: "Marcar como lida"),
                backgroundColor: KCDesign.accent
            ) { [weak self] _, _, completion in
                Task {
                    _ = await self?.viewModel.markRead(id: item.id)
                    await MainActor.run { completion(true) }
                }
            }
            actions.append(markRead)
        }

        let config = UISwipeActionsConfiguration(actions: actions)
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
        backgroundColor = KCDesign.surface
        selectedBackgroundView = {
            let view = UIView()
            view.backgroundColor = KCDesign.accentSoft
            return view
        }()

        iconWrap.translatesAutoresizingMaskIntoConstraints = false
        iconWrap.backgroundColor = KCDesign.accentSoft
        iconWrap.layer.cornerRadius = KCDesign.Radius.md
        iconWrap.layer.cornerCurve = .continuous

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = KCDesign.accent
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        iconWrap.addSubview(iconView)

        unreadDot.translatesAutoresizingMaskIntoConstraints = false
        unreadDot.backgroundColor = KCDesign.accent
        unreadDot.layer.cornerRadius = 4
        unreadDot.isHidden = true

        titleLabel.font = KCDesign.rowTitle()
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 2
        titleLabel.adjustsFontForContentSizeCategory = true

        bodyLabel.font = KCDesign.rowSubtitle()
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.numberOfLines = 3
        bodyLabel.adjustsFontForContentSizeCategory = true

        timeLabel.font = KCDesign.caption()
        timeLabel.textColor = .tertiaryLabel
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        timeLabel.adjustsFontForContentSizeCategory = true

        titleRow.axis = .horizontal
        titleRow.alignment = .firstBaseline
        titleRow.spacing = KCDesign.Space.sm
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
            iconWrap.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: KCDesign.Space.md),
            iconWrap.topAnchor.constraint(equalTo: contentView.topAnchor, constant: KCDesign.Space.md),
            iconWrap.widthAnchor.constraint(equalToConstant: 36),
            iconWrap.heightAnchor.constraint(equalToConstant: 36),

            iconView.centerXAnchor.constraint(equalTo: iconWrap.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconWrap.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            unreadDot.leadingAnchor.constraint(equalTo: iconWrap.trailingAnchor, constant: KCDesign.Space.sm),
            unreadDot.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            unreadDot.widthAnchor.constraint(equalToConstant: 8),
            unreadDot.heightAnchor.constraint(equalToConstant: 8),

            textStack.leadingAnchor.constraint(equalTo: unreadDot.trailingAnchor, constant: KCDesign.Space.sm),
            textStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -KCDesign.Space.md),
            textStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: KCDesign.Space.md),
            textStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -KCDesign.Space.md),
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
        backgroundColor = unread ? KCDesign.accentSoft : KCDesign.surface
        titleLabel.font = unread
            ? KCDesign.preferred(.body, weight: .semibold)
            : KCDesign.preferred(.body, weight: .regular)

        accessibilityLabel = [item.title, item.body, timeLabel.text]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
        accessibilityValue = unread ? String(localized: "Não lido") : nil
    }
}
