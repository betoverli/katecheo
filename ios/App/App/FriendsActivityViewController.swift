import UIKit

/// Profile → Amigos (build-238).
///
/// Web already has `listLinks` / `acceptLink` / `declineLink` (+ acceptance push via
/// `notifySocial` kind=friends). Native `/api/native/v1` has **no** friends/links routes,
/// so this screen must not pretend pending dots are actionable. Friend chrome dots stay
/// gated (`V2NActivityStore.friendsDotsEnabled == false`) until Beto approves the wrap.
final class FriendsActivityViewController: UITableViewController {
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
        // Never leave stale pending items that could re-enable chrome if the gate flips later.
        V2NActivityStore.clearKind(.friendPending)
        V2NActivityStore.markFriendsAcceptedSeen()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 1 }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        String(localized: "Pedidos e aceites")
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        String(localized: "Listar, aceitar e recusar pedidos exige wrapping nativo das rotas web de amigos (listLinks / acceptLink / declineLink). Sem isso, o iOS não mostra bolinha em Perfil — evita beco sem saída.")
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "friend", for: indexPath)
        var config = cell.defaultContentConfiguration()
        config.text = String(localized: "Aguardando API nativa")
        config.secondaryText = String(localized: "No web já funciona; no app iOS ainda não há endpoints Bearer.")
        config.image = UIImage(systemName: "person.2")
        cell.contentConfiguration = config
        cell.selectionStyle = .none
        cell.v2nApplyThemedGroupedCell()
        return cell
    }
}
