import UIKit

/// Profile → Amigos: list / accept / decline via native `/links` (build-238).
/// Pending requests stay until a decision. Acceptance inbox signals clear on appear.
final class FriendsActivityViewController: UITableViewController {
    private var friends: [NativeAPIClient.LinkPersonDTO] = []
    private var incoming: [NativeAPIClient.LinkPersonDTO] = []
    private var outgoing: [NativeAPIClient.LinkPersonDTO] = []
    private var loading = false

    init() {
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        v2nApplyGroupedChrome()
        title = String(localized: "Amigos")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "friend")
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(pullRefresh), for: .valueChanged)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Acceptance dots only — never clear pending by visiting the screen.
        V2NActivityStore.markFriendsAcceptedSeen()
        Task { await reload() }
    }

    @objc private func pullRefresh() {
        Task { await reload() }
    }

    private func reload() async {
        guard NativeAPIClient.hasBearer else {
            await MainActor.run {
                friends = []; incoming = []; outgoing = []
                tableView.reloadData()
                refreshControl?.endRefreshing()
            }
            return
        }
        loading = true
        do {
            let pack = try await NativeAPIClient.listLinks()
            await V2NActivitySync.refreshFromServer()
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
                let alert = UIAlertController(
                    title: String(localized: "Erro"),
                    message: error.localizedDescription,
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
                self.present(alert, animated: true)
            }
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 3 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return max(incoming.count, 1)
        case 1: return max(friends.count, 1)
        default: return max(outgoing.count, 1)
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return String(localized: "Pedidos pendentes")
        case 1: return String(localized: "Amigos")
        default: return String(localized: "Pedidos enviados")
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 {
            return String(localized: "Pedidos só saem da lista depois de aceitar ou recusar.")
        }
        return nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "friend", for: indexPath)
        var config = cell.defaultContentConfiguration()
        cell.accessoryType = .none
        cell.selectionStyle = .none

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
                config.secondaryText = String(localized: "Aguardando resposta")
                config.image = UIImage(systemName: "paperplane")
            }
        }

        cell.contentConfiguration = config
        cell.v2nApplyThemedGroupedCell()
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 0, !incoming.isEmpty else { return }
        let person = incoming[indexPath.row]
        presentDecision(for: person)
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
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = tableView
            pop.sourceRect = tableView.bounds
        }
        present(sheet, animated: true)
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
            V2NActivityStore.clearFriendPending(targetId: handle)
            V2NActivityStore.clearFriendPending(targetId: person.userId)
            await reload()
        } catch {
            await MainActor.run {
                let alert = UIAlertController(
                    title: String(localized: "Erro"),
                    message: error.localizedDescription,
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
                self.present(alert, animated: true)
            }
        }
    }
}
