import UIKit

/// Profile → Amigos: reachable destination for friend activity dots (build-238).
///
/// Backend gap: there is no `/api/native/v1/friends` (list / accept / decline).
/// Pending requests therefore stay until a push-sourced clear or sign-out; acceptances
/// clear when this screen is opened. Do not invent remote friend rows.
final class FriendsActivityViewController: UITableViewController {
    private var pending: [V2NActivityStore.Item] = []
    private var accepted: [V2NActivityStore.Item] = []

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
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
        // Accepted friendships clear once the reachable Friends screen is seen.
        V2NActivityStore.markFriendsAcceptedSeen()
    }

    private func reload() {
        pending = V2NActivityStore.items(kind: .friendPending)
        accepted = V2NActivityStore.items(kind: .friendAccepted)
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 { return max(pending.count, 1) }
        return max(accepted.count, 1)
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? String(localized: "Pedidos pendentes") : String(localized: "Aceites recentes")
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 {
            return String(localized: "Aceitar ou recusar pedidos ainda não está disponível neste app iOS — falta a API nativa de amigos.")
        }
        return nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "friend", for: indexPath)
        var config = cell.defaultContentConfiguration()
        if indexPath.section == 0 {
            if pending.isEmpty {
                config.text = String(localized: "Nenhum pedido pendente")
                config.secondaryText = String(localized: "Quando alguém te enviar um pedido, ele aparece aqui.")
                cell.selectionStyle = .none
            } else {
                let item = pending[indexPath.row]
                config.text = item.title ?? String(localized: "Pedido de amizade")
                config.secondaryText = String(localized: "Pendente — aguardando API nativa")
                cell.selectionStyle = .none
            }
            config.image = UIImage(systemName: "person.badge.plus")
        } else {
            if accepted.isEmpty {
                config.text = String(localized: "Nenhum aceite recente")
                cell.selectionStyle = .none
            } else {
                let item = accepted[indexPath.row]
                config.text = item.title ?? String(localized: "Amizade aceita")
                cell.selectionStyle = .none
            }
            config.image = UIImage(systemName: "person.2")
        }
        cell.contentConfiguration = config
        cell.v2nApplyThemedGroupedCell()
        return cell
    }
}
