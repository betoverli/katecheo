import UIKit

/// Profile → Amigos: friends first; pending/sent only when non-empty; inline accept/decline.
final class FriendsActivityViewController: UITableViewController, UISearchResultsUpdating {
    private enum Section: Hashable {
        case incoming
        case outgoing
        case friends
        case search
    }

    private var friends: [NativeAPIClient.LinkPersonDTO] = []
    private var incoming: [NativeAPIClient.LinkPersonDTO] = []
    private var outgoing: [NativeAPIClient.LinkPersonDTO] = []
    private var hits: [NativeAPIClient.PeopleHitDTO] = []
    private var loading = false
    private var busyHandle: String?
    /// When true, `reload` keeps injected fixtures (ConfirmationDialogTests screenshots).
    private var testingSkipNetworkReload = false
    private let search = UISearchController(searchResultsController: nil)
    private var searchWork: DispatchWorkItem?

    init() {
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        kcApplyGroupedChrome()
        title = String(localized: "Amigos")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "friend")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 52
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(pullRefresh), for: .valueChanged)

        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = String(localized: "Buscar por @usuário")
        search.searchBar.autocapitalizationType = .none
        search.searchBar.autocorrectionType = .no
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        KCActivityStore.markFriendsAcceptedSeen()
        Task { await reload(force: false) }
    }

    @objc private func pullRefresh() {
        Task { await reload(force: true) }
    }

    private var isSearching: Bool {
        (search.searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    /// Incoming / sent only when non-empty, above friends. Friends always last (or alone).
    private var visibleSections: [Section] {
        if isSearching { return [.search] }
        var sections: [Section] = []
        if !incoming.isEmpty { sections.append(.incoming) }
        if !outgoing.isEmpty { sections.append(.outgoing) }
        sections.append(.friends)
        return sections
    }

    private func section(at index: Int) -> Section {
        let sections = visibleSections
        guard index >= 0, index < sections.count else { return .friends }
        return sections[index]
    }

    /// Test-only fixture injection for light/dark screenshot coverage.
    func testing_setLinks(
        friends: [NativeAPIClient.LinkPersonDTO],
        incoming: [NativeAPIClient.LinkPersonDTO],
        outgoing: [NativeAPIClient.LinkPersonDTO]
    ) {
        testingSkipNetworkReload = true
        self.friends = friends
        self.incoming = incoming
        self.outgoing = outgoing
        tableView.reloadData()
    }

    private func reload(force: Bool = false) async {
        if testingSkipNetworkReload {
            await MainActor.run {
                self.loading = false
                self.tableView.reloadData()
                self.refreshControl?.endRefreshing()
            }
            return
        }
        guard NativeAPIClient.hasBearer else {
            await MainActor.run {
                friends = []; incoming = []; outgoing = []; hits = []
                tableView.reloadData()
                refreshControl?.endRefreshing()
            }
            return
        }
        loading = true
        do {
            let pack = try await NativeAPIClient.listLinks()
            await KCActivitySync.refreshFromServer(force: force)
            await MainActor.run {
                self.friends = pack.friends
                self.incoming = pack.incoming
                self.outgoing = pack.outgoing
                self.loading = false
                self.tableView.reloadData()
                self.refreshControl?.endRefreshing()
            }
        } catch {
            await MainActor.run {
                self.loading = false
                self.refreshControl?.endRefreshing()
                self.presentError(error.localizedDescription)
            }
        }
    }

    func updateSearchResults(for searchController: UISearchController) {
        searchWork?.cancel()
        let q = (searchController.searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else {
            hits = []
            tableView.reloadData()
            return
        }
        let work = DispatchWorkItem { [weak self] in
            Task { await self?.runSearch(q) }
        }
        searchWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func runSearch(_ q: String) async {
        guard NativeAPIClient.hasBearer else { return }
        do {
            let people = try await NativeAPIClient.searchPeople(query: q)
            await MainActor.run {
                self.hits = people
                self.tableView.reloadData()
            }
        } catch {
            await MainActor.run {
                self.hits = []
                self.tableView.reloadData()
            }
        }
    }

    // MARK: - Table

    override func numberOfSections(in tableView: UITableView) -> Int {
        visibleSections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection sectionIndex: Int) -> Int {
        switch section(at: sectionIndex) {
        case .search: return max(hits.count, 1)
        case .incoming: return incoming.count
        case .outgoing: return outgoing.count
        case .friends: return max(friends.count, 1)
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection sectionIndex: Int) -> String? {
        switch section(at: sectionIndex) {
        case .search:
            return String(localized: "Resultados")
        case .incoming:
            return String(format: String(localized: "Pedidos pendentes (%lld)"), incoming.count)
        case .outgoing:
            return String(format: String(localized: "Pedidos enviados (%lld)"), outgoing.count)
        case .friends:
            return String(localized: "Amigos")
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection sectionIndex: Int) -> String? {
        if section(at: sectionIndex) == .search {
            return String(localized: "Digite pelo menos 2 caracteres.")
        }
        return nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "friend", for: indexPath)
        var config = compactConfig()
        cell.accessoryType = .none
        cell.accessoryView = nil
        cell.selectionStyle = .none
        cell.backgroundColor = KCDesign.surface

        switch section(at: indexPath.section) {
        case .search:
            if hits.isEmpty {
                config.text = String(localized: "Ninguém encontrado")
                config.secondaryText = String(localized: "Confira o @usuário.")
                config.image = UIImage(systemName: "magnifyingglass")
            } else {
                let hit = hits[indexPath.row]
                config.text = hit.asPerson.displayName
                config.secondaryText = hit.handle.isEmpty ? nil : "@\(hit.handle)"
                config.image = UIImage(systemName: "person.crop.circle")
                cell.selectionStyle = .default
                cell.accessoryType = .disclosureIndicator
            }

        case .incoming:
            let person = incoming[indexPath.row]
            config.text = person.displayName
            config.secondaryText = person.handle.isEmpty ? nil : "@\(person.handle)"
            config.image = UIImage(systemName: "person.badge.plus")
            cell.accessoryView = incomingAccessory(for: person)

        case .outgoing:
            let person = outgoing[indexPath.row]
            config.text = person.displayName
            config.secondaryText = person.handle.isEmpty ? nil : "@\(person.handle)"
            config.image = UIImage(systemName: "paperplane")
            cell.accessoryView = outgoingAccessory(for: person)

        case .friends:
            if friends.isEmpty {
                config.text = String(localized: "Nenhum amigo ainda")
                config.secondaryText = loading
                    ? String(localized: "Carregando…")
                    : String(localized: "Busque pelo @usuário.")
                config.image = UIImage(systemName: "person.2")
            } else {
                let person = friends[indexPath.row]
                config.text = person.displayName
                config.secondaryText = person.handle.isEmpty ? nil : "@\(person.handle)"
                config.image = UIImage(systemName: "person.crop.circle.fill")
                cell.selectionStyle = .default
            }
        }

        cell.contentConfiguration = config
        cell.kcApplyThemedGroupedCell()
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch section(at: indexPath.section) {
        case .search:
            guard !hits.isEmpty else { return }
            presentHitActions(hits[indexPath.row], at: indexPath)
        case .friends:
            guard !friends.isEmpty else { return }
            presentFriendMenu(for: friends[indexPath.row], at: indexPath)
        case .incoming, .outgoing:
            break
        }
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        switch section(at: indexPath.section) {
        case .friends:
            guard !friends.isEmpty else { return nil }
            let person = friends[indexPath.row]
            let remove = UIContextualAction.kcIconOnly(
                style: .destructive,
                systemName: "person.badge.minus",
                accessibilityLabel: String(localized: "Remover amigo")
            ) { [weak self] _, _, done in
                self?.confirmRemoveFriend(person, at: indexPath)
                done(true)
            }
            return UISwipeActionsConfiguration(actions: [remove])

        case .outgoing:
            let person = outgoing[indexPath.row]
            let cancel = UIContextualAction.kcIconOnly(
                style: .destructive,
                systemName: "xmark",
                accessibilityLabel: String(localized: "Cancelar pedido")
            ) { [weak self] _, _, done in
                self?.confirmCancelOutgoing(person, at: indexPath)
                done(true)
            }
            return UISwipeActionsConfiguration(actions: [cancel])

        case .incoming:
            let person = incoming[indexPath.row]
            let decline = UIContextualAction.kcIconOnly(
                style: .destructive,
                systemName: "xmark",
                accessibilityLabel: String(localized: "Recusar")
            ) { [weak self] _, _, done in
                Task { await self?.decide(person: person, accept: false) }
                done(true)
            }
            return UISwipeActionsConfiguration(actions: [decline])

        case .search:
            return nil
        }
    }

    override func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard section(at: indexPath.section) == .friends, !friends.isEmpty else { return nil }
        let person = friends[indexPath.row]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            let remove = UIAction(
                title: String(localized: "Remover amigo"),
                image: UIImage(systemName: "person.badge.minus"),
                attributes: .destructive
            ) { _ in
                self?.confirmRemoveFriend(person, at: indexPath)
            }
            return UIMenu(children: [remove])
        }
    }

    // MARK: - Compact chrome + accessories

    private func compactConfig() -> UIListContentConfiguration {
        var config = UIListContentConfiguration.subtitleCell()
        config.textProperties.font = .preferredFont(forTextStyle: .body)
        config.secondaryTextProperties.font = .preferredFont(forTextStyle: .footnote)
        config.secondaryTextProperties.color = .secondaryLabel
        config.imageProperties.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        config.imageProperties.tintColor = KCDesign.accent
        config.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 8)
        config.imageToTextPadding = 10
        return config
    }

    private func incomingAccessory(for person: NativeAPIClient.LinkPersonDTO) -> UIView {
        let decline = compactButton(
            title: String(localized: "Recusar"),
            color: .systemRed
        ) { [weak self] in
            Task { await self?.decide(person: person, accept: false) }
        }
        let accept = compactButton(
            title: String(localized: "Aceitar"),
            color: KCDesign.accent,
            emphasized: true
        ) { [weak self] in
            Task { await self?.decide(person: person, accept: true) }
        }
        return accessoryStack([decline, accept])
    }

    private func outgoingAccessory(for person: NativeAPIClient.LinkPersonDTO) -> UIView {
        let cancel = compactButton(
            title: String(localized: "Cancelar"),
            color: .systemRed
        ) { [weak self] in
            guard let self else { return }
            let index = self.outgoing.firstIndex(where: { $0.userId == person.userId }) ?? 0
            let sectionIndex = self.visibleSections.firstIndex(of: .outgoing) ?? 0
            self.confirmCancelOutgoing(person, at: IndexPath(row: index, section: sectionIndex))
        }
        return accessoryStack([cancel])
    }

    private func compactButton(title: String, color: UIColor, emphasized: Bool = false, action: @escaping () -> Void) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.title = title
        config.baseForegroundColor = color
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .preferredFont(forTextStyle: .subheadline)
            if emphasized {
                outgoing.font = .preferredFont(forTextStyle: .subheadline).withWeight(.semibold)
                    ?? outgoing.font
            }
            return outgoing
        }
        let button = UIButton(configuration: config, primaryAction: UIAction { _ in action() })
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }

    private func accessoryStack(_ buttons: [UIView]) -> UIView {
        let stack = UIStackView(arrangedSubviews: buttons)
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 2
        stack.sizeToFit()
        return stack
    }

    // MARK: - Actions / confirmations

    private func presentHitActions(_ hit: NativeAPIClient.PeopleHitDTO, at indexPath: IndexPath) {
        let person = hit.asPerson
        let sheet = UIAlertController(title: person.displayName, message: nil, preferredStyle: .actionSheet)
        switch hit.status {
        case "accepted":
            sheet.message = String(localized: "Vocês já são amigos.")
            sheet.addAction(UIAlertAction(title: String(localized: "Remover amigo"), style: .destructive) { [weak self] _ in
                self?.confirmRemoveFriend(person, at: indexPath)
            })
        case "outgoing":
            sheet.message = String(localized: "Pedido já enviado.")
            sheet.addAction(UIAlertAction(title: String(localized: "Cancelar pedido"), style: .destructive) { [weak self] _ in
                Task { await self?.decline(handle: hit.handle) }
            })
        case "incoming":
            sheet.addAction(UIAlertAction(title: String(localized: "Aceitar"), style: .default) { [weak self] _ in
                Task { await self?.decide(person: person, accept: true) }
            })
            sheet.addAction(UIAlertAction(title: String(localized: "Recusar"), style: .destructive) { [weak self] _ in
                Task { await self?.decide(person: person, accept: false) }
            })
        default:
            sheet.addAction(UIAlertAction(title: String(localized: "Enviar pedido"), style: .default) { [weak self] _ in
                Task { await self?.request(handle: hit.handle) }
            })
        }
        sheet.addAction(UIAlertAction(title: String(localized: "Cancelar"), style: .cancel))
        presentSheet(sheet, at: indexPath)
    }

    private func presentFriendMenu(for person: NativeAPIClient.LinkPersonDTO, at indexPath: IndexPath) {
        let sheet = UIAlertController(title: person.displayName, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: String(localized: "Remover amigo"), style: .destructive) { [weak self] _ in
            self?.confirmRemoveFriend(person, at: indexPath)
        })
        sheet.addAction(UIAlertAction(title: String(localized: "Cancelar"), style: .cancel))
        presentSheet(sheet, at: indexPath)
    }

    private func confirmRemoveFriend(_ person: NativeAPIClient.LinkPersonDTO, at indexPath: IndexPath) {
        let sheet = UIAlertController(
            title: String(localized: "Remover amigo?"),
            message: String(localized: "Vocês deixam de ser amigos nos dois lados."),
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: String(localized: "Cancelar"), style: .cancel))
        sheet.addAction(UIAlertAction(title: String(localized: "Remover amigo"), style: .destructive) { [weak self] _ in
            Task { await self?.removeFriend(person) }
        })
        presentSheet(sheet, at: indexPath)
    }

    private func confirmCancelOutgoing(_ person: NativeAPIClient.LinkPersonDTO, at indexPath: IndexPath) {
        let sheet = UIAlertController(
            title: String(localized: "Cancelar pedido?"),
            message: person.handle.isEmpty ? nil : "@\(person.handle)",
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: String(localized: "Voltar"), style: .cancel))
        sheet.addAction(UIAlertAction(title: String(localized: "Cancelar pedido"), style: .destructive) { [weak self] _ in
            Task { await self?.decline(handle: person.handle) }
        })
        presentSheet(sheet, at: indexPath)
    }

    private func presentSheet(_ sheet: UIAlertController, at indexPath: IndexPath? = nil) {
        let rect = indexPath.map { tableView.rectForRow(at: $0) }
        KCConfirmation.presentActionSheet(
            sheet,
            from: self,
            sourceView: tableView,
            sourceRect: (rect?.isEmpty == false) ? rect : nil
        )
    }

    private func request(handle: String) async {
        guard !handle.isEmpty, busyHandle == nil else { return }
        busyHandle = handle
        do {
            _ = try await NativeAPIClient.requestLink(handle: handle)
            await reload(force: true)
            await MainActor.run {
                self.search.searchBar.text = ""
                self.hits = []
                self.tableView.reloadData()
            }
        } catch {
            await MainActor.run {
                self.presentError(Self.mapLinkError(error))
            }
        }
        busyHandle = nil
    }

    private func decline(handle: String) async {
        guard !handle.isEmpty else { return }
        do {
            try await NativeAPIClient.declineLink(handle: handle)
            KCActivityStore.clearFriendPending(targetId: handle)
            await reload(force: true)
        } catch {
            await MainActor.run { self.presentError(error.localizedDescription) }
        }
    }

    private func removeFriend(_ person: NativeAPIClient.LinkPersonDTO) async {
        let handle = person.handle
        guard !handle.isEmpty else { return }
        do {
            try await NativeAPIClient.removeLink(handle: handle)
            await reload(force: true)
        } catch {
            await MainActor.run { self.presentError(error.localizedDescription) }
        }
    }

    private func decide(person: NativeAPIClient.LinkPersonDTO, accept: Bool) async {
        let handle = person.handle
        guard !handle.isEmpty else { return }
        do {
            if accept {
                try await NativeAPIClient.acceptLink(handle: handle)
            } else {
                try await NativeAPIClient.declineLink(handle: handle)
            }
            KCActivityStore.clearFriendPending(targetId: handle)
            KCActivityStore.clearFriendPending(targetId: person.userId)
            await reload(force: true)
        } catch {
            await MainActor.run { self.presentError(error.localizedDescription) }
        }
    }

    private func presentError(_ message: String) {
        let alert = UIAlertController(title: String(localized: "Erro"), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
        present(alert, animated: true)
    }

    private static func mapLinkError(_ error: Error) -> String {
        if case NativeAPIClient.APIError.http(_, let body) = error {
            if body.contains("missing") {
                return String(localized: "Não encontramos esse @usuário.")
            }
            if body.contains("limit") || body.contains("rate") {
                return String(localized: "Limite de pedidos atingido. Tente mais tarde.")
            }
        }
        return error.localizedDescription
    }
}

private extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont? {
        let descriptor = fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight],
        ])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
