import UIKit

/// Profile → Amigos: list / search / request / accept / decline via native `/links`.
/// Identifier = @handle (same as web). Cancel sent = decline. Pending stays until decision.
final class FriendsActivityViewController: UITableViewController, UISearchResultsUpdating {
    private var friends: [NativeAPIClient.LinkPersonDTO] = []
    private var incoming: [NativeAPIClient.LinkPersonDTO] = []
    private var outgoing: [NativeAPIClient.LinkPersonDTO] = []
    private var hits: [NativeAPIClient.PeopleHitDTO] = []
    private var loading = false
    private var busyHandle: String?
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

    private func reload(force: Bool = false) async {
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

    override func numberOfSections(in tableView: UITableView) -> Int {
        isSearching ? 1 : 3
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if isSearching { return max(hits.count, 1) }
        switch section {
        case 0: return max(incoming.count, 1)
        case 1: return max(friends.count, 1)
        default: return max(outgoing.count, 1)
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if isSearching { return String(localized: "Resultados") }
        switch section {
        case 0: return String(localized: "Pedidos pendentes")
        case 1: return String(localized: "Amigos")
        default: return String(localized: "Pedidos enviados")
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if isSearching {
            return String(localized: "Digite pelo menos 2 caracteres do @usuário ou nome.")
        }
        if section == 0 {
            return String(localized: "Pedidos só saem da lista depois de aceitar ou recusar.")
        }
        if section == 2 {
            return String(localized: "Toque em um pedido enviado para cancelar.")
        }
        return nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "friend", for: indexPath)
        var config = cell.defaultContentConfiguration()
        cell.accessoryType = .none
        cell.selectionStyle = .none

        if isSearching {
            if hits.isEmpty {
                config.text = String(localized: "Ninguém encontrado")
                config.secondaryText = String(localized: "Confira o @usuário e tente de novo.")
                config.image = UIImage(systemName: "magnifyingglass")
            } else {
                let hit = hits[indexPath.row]
                config.text = hit.asPerson.displayName
                config.secondaryText = hit.handle.isEmpty ? nil : "@\(hit.handle)"
                config.image = UIImage(systemName: "person.crop.circle.badge.plus")
                cell.selectionStyle = .default
                cell.accessoryType = .disclosureIndicator
            }
            cell.contentConfiguration = config
            cell.kcApplyThemedGroupedCell()
            return cell
        }

        switch indexPath.section {
        case 0:
            if incoming.isEmpty {
                config.text = String(localized: "Nenhum pedido pendente")
                config.secondaryText = loading
                    ? String(localized: "Carregando…")
                    : String(localized: "Quando alguém te enviar um pedido, ele aparece aqui.")
                config.image = UIImage(systemName: "person.badge.plus")
            } else {
                let person = incoming[indexPath.row]
                config.text = person.displayName
                config.secondaryText = person.handle.isEmpty ? nil : "@\(person.handle)"
                config.image = UIImage(systemName: "person.badge.plus")
                cell.selectionStyle = .default
                cell.accessoryType = .disclosureIndicator
            }
        case 1:
            if friends.isEmpty {
                config.text = String(localized: "Nenhum amigo ainda")
                config.secondaryText = String(localized: "Use a busca acima para adicionar pelo @usuário.")
                config.image = UIImage(systemName: "person.2")
            } else {
                let person = friends[indexPath.row]
                config.text = person.displayName
                config.secondaryText = person.handle.isEmpty ? nil : "@\(person.handle)"
                config.image = UIImage(systemName: "person.2.fill")
            }
        default:
            if outgoing.isEmpty {
                config.text = String(localized: "Nenhum pedido enviado")
                config.image = UIImage(systemName: "paperplane")
            } else {
                let person = outgoing[indexPath.row]
                config.text = person.displayName
                config.secondaryText = String(localized: "Aguardando resposta · toque para cancelar")
                config.image = UIImage(systemName: "paperplane")
                cell.selectionStyle = .default
                cell.accessoryType = .disclosureIndicator
            }
        }

        cell.contentConfiguration = config
        cell.kcApplyThemedGroupedCell()
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if isSearching {
            guard !hits.isEmpty else { return }
            presentHitActions(hits[indexPath.row])
            return
        }
        if indexPath.section == 0, !incoming.isEmpty {
            presentDecision(for: incoming[indexPath.row])
        } else if indexPath.section == 2, !outgoing.isEmpty {
            presentCancel(for: outgoing[indexPath.row])
        }
    }

    private func presentHitActions(_ hit: NativeAPIClient.PeopleHitDTO) {
        let person = hit.asPerson
        let sheet = UIAlertController(title: person.displayName, message: nil, preferredStyle: .actionSheet)
        switch hit.status {
        case "accepted":
            sheet.message = String(localized: "Vocês já são amigos.")
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
        sheet.addAction(UIAlertAction(title: String(localized: "Fechar"), style: .cancel))
        presentSheet(sheet)
    }

    private func presentDecision(for person: NativeAPIClient.LinkPersonDTO) {
        let sheet = UIAlertController(
            title: person.displayName,
            message: String(localized: "Aceitar ou recusar este pedido de amizade?"),
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: String(localized: "Aceitar"), style: .default) { [weak self] _ in
            Task { await self?.decide(person: person, accept: true) }
        })
        sheet.addAction(UIAlertAction(title: String(localized: "Recusar"), style: .destructive) { [weak self] _ in
            Task { await self?.decide(person: person, accept: false) }
        })
        sheet.addAction(UIAlertAction(title: String(localized: "Cancelar"), style: .cancel))
        presentSheet(sheet)
    }

    private func presentCancel(for person: NativeAPIClient.LinkPersonDTO) {
        let sheet = UIAlertController(
            title: person.displayName,
            message: String(localized: "Cancelar este pedido enviado?"),
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: String(localized: "Cancelar pedido"), style: .destructive) { [weak self] _ in
            Task { await self?.decline(handle: person.handle) }
        })
        sheet.addAction(UIAlertAction(title: String(localized: "Manter"), style: .cancel))
        presentSheet(sheet)
    }

    private func presentSheet(_ sheet: UIAlertController) {
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = tableView
            pop.sourceRect = tableView.bounds
        }
        present(sheet, animated: true)
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
