import UIKit

/// Shared report / block flows (App Store Guideline 1.2) + blocked-users list.
enum ReportBlockSupport {
    enum Target {
        case user(userId: String, displayName: String)
        case note(noteId: String, authorUserId: String?, authorName: String)
        case group(groupId: String, name: String)

        var reportType: String {
            switch self {
            case .user: return "user"
            case .note: return "note"
            case .group: return "group"
            }
        }

        var reportId: String {
            switch self {
            case .user(let id, _): return id
            case .note(let id, _, _): return id
            case .group(let id, _): return id
            }
        }

        var blockUserId: String? {
            switch self {
            case .user(let id, _): return id
            case .note(_, let author, _): return author
            case .group: return nil
            }
        }

        var displayName: String {
            switch self {
            case .user(_, let name): return name
            case .note(_, _, let name): return name
            case .group(_, let name): return name
            }
        }
    }

    enum Reason: String, CaseIterable {
        case spam
        case offensive
        case inappropriate
        case other

        var title: String {
            switch self {
            case .spam: return String(localized: "Spam")
            case .offensive: return String(localized: "Ofensivo ou abusivo")
            case .inappropriate: return String(localized: "Conteúdo impróprio")
            case .other: return String(localized: "Outro")
            }
        }
    }

    /// Report + Block actions for a person (friend / member).
    static func personMenuActions(
        userId: String,
        displayName: String,
        host: UIViewController,
        sourceView: UIView? = nil,
        sourceRect: CGRect? = nil,
        barButtonItem: UIBarButtonItem? = nil,
        onBlocked: (() -> Void)? = nil
    ) -> [UIAlertAction] {
        let target = Target.user(userId: userId, displayName: displayName)
        let report = UIAlertAction(title: String(localized: "Denunciar"), style: .default) { _ in
            presentReport(target: target, from: host, sourceView: sourceView, sourceRect: sourceRect, barButtonItem: barButtonItem)
        }
        let block = UIAlertAction(title: String(localized: "Bloquear"), style: .destructive) { _ in
            confirmBlock(userId: userId, displayName: displayName, from: host, sourceView: sourceView, sourceRect: sourceRect, barButtonItem: barButtonItem, onBlocked: onBlocked)
        }
        return [report, block]
    }

    static func presentReport(
        target: Target,
        from host: UIViewController,
        sourceView: UIView? = nil,
        sourceRect: CGRect? = nil,
        barButtonItem: UIBarButtonItem? = nil
    ) {
        let sheet = UIAlertController(
            title: String(localized: "Denunciar"),
            message: String(localized: "Escolha o motivo. A equipe Katecheo analisa cada denúncia."),
            preferredStyle: .actionSheet
        )
        for reason in Reason.allCases {
            sheet.addAction(UIAlertAction(title: reason.title, style: .default) { _ in
                if reason == .other {
                    promptDetails(target: target, reason: reason, from: host)
                } else {
                    confirmReport(target: target, reason: reason, details: "", from: host)
                }
            })
        }
        sheet.addAction(UIAlertAction(title: String(localized: "Cancelar"), style: .cancel))
        KCConfirmation.presentActionSheet(
            sheet,
            from: host,
            sourceView: sourceView,
            sourceRect: sourceRect,
            barButtonItem: barButtonItem
        )
    }

    private static func promptDetails(target: Target, reason: Reason, from host: UIViewController) {
        let alert = UIAlertController(
            title: String(localized: "Detalhes (opcional)"),
            message: String(localized: "Descreva o problema em poucas palavras."),
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = String(localized: "Detalhes")
            field.autocapitalizationType = .sentences
            field.returnKeyType = .done
        }
        alert.addAction(UIAlertAction(title: String(localized: "Cancelar"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "Enviar denúncia"), style: .destructive) { _ in
            let details = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            confirmReport(target: target, reason: reason, details: details, from: host)
        })
        host.present(alert, animated: true)
    }

    private static func confirmReport(target: Target, reason: Reason, details: String, from host: UIViewController) {
        let alert = UIAlertController(
            title: String(localized: "Enviar denúncia?"),
            message: String(localized: "Vamos analisar e tomar as medidas necessárias."),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "Cancelar"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "Enviar denúncia"), style: .destructive) { _ in
            Task { @MainActor in
                do {
                    try await NativeAPIClient.reportContent(
                        targetType: target.reportType,
                        targetId: target.reportId,
                        reason: reason.rawValue,
                        details: details
                    )
                    KCToast.show(String(localized: "Denúncia enviada"), on: host)
                } catch {
                    presentError(error, on: host)
                }
            }
        })
        host.present(alert, animated: true)
    }

    static func confirmBlock(
        userId: String,
        displayName: String,
        from host: UIViewController,
        sourceView: UIView? = nil,
        sourceRect: CGRect? = nil,
        barButtonItem: UIBarButtonItem? = nil,
        onBlocked: (() -> Void)? = nil
    ) {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? String(localized: "esta pessoa")
            : displayName
        let sheet = UIAlertController(
            title: String(format: String(localized: "Bloquear %@?"), name),
            message: String(localized: "Vocês deixam de ser amigos. Conteúdo compartilhado some da sua lista. A pessoa não pode enviar pedidos de amizade."),
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: String(localized: "Cancelar"), style: .cancel))
        sheet.addAction(UIAlertAction(title: String(localized: "Bloquear"), style: .destructive) { _ in
            Task { @MainActor in
                do {
                    try await NativeAPIClient.blockUser(userId: userId)
                    NativeSWR.invalidate(.granted)
                    NativeSWR.invalidate(.groups)
                    KCToast.show(String(localized: "Usuário bloqueado"), on: host)
                    onBlocked?()
                } catch {
                    presentError(error, on: host)
                }
            }
        })
        KCConfirmation.presentActionSheet(
            sheet,
            from: host,
            sourceView: sourceView,
            sourceRect: sourceRect,
            barButtonItem: barButtonItem
        )
    }

    private static func presentError(_ error: Error, on host: UIViewController) {
        let alert = UIAlertController(
            title: String(localized: "Erro"),
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
        host.present(alert, animated: true)
    }
}

/// Brief success toast — fades in over the bottom of the host.
enum KCToast {
    @MainActor
    static func show(_ message: String, on host: UIViewController, duration: TimeInterval = 1.8) {
        let label = UILabel()
        label.text = message
        label.textAlignment = .center
        label.font = KCDesign.preferred(.subheadline, weight: .semibold)
        label.textColor = .white
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false

        let bubble = UIView()
        bubble.backgroundColor = UIColor.label.withAlphaComponent(0.88)
        bubble.layer.cornerRadius = 14
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.alpha = 0
        bubble.addSubview(label)
        host.view.addSubview(bubble)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -12),
            label.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -18),
            bubble.centerXAnchor.constraint(equalTo: host.view.centerXAnchor),
            bubble.leadingAnchor.constraint(greaterThanOrEqualTo: host.view.layoutMarginsGuide.leadingAnchor),
            bubble.trailingAnchor.constraint(lessThanOrEqualTo: host.view.layoutMarginsGuide.trailingAnchor),
            bubble.bottomAnchor.constraint(equalTo: host.view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
        ])

        UIView.animate(withDuration: 0.22, animations: { bubble.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.28, delay: duration, options: [.curveEaseIn]) {
                bubble.alpha = 0
            } completion: { _ in
                bubble.removeFromSuperview()
            }
        }
    }
}

/// Profile → Conta → Usuários bloqueados.
final class BlockedUsersViewController: UITableViewController {
    private var blocks: [NativeAPIClient.BlockedPersonDTO] = []
    private let emptyState = KCEmptyStateView()
    private var loading = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "Usuários bloqueados")
        KCChrome.styleScreen(view)
        KCChrome.styleGroupedTable(tableView)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "blocked")
        navigationItem.largeTitleDisplayMode = .never
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(reload), for: .valueChanged)

        emptyState.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyState)
        NSLayoutConstraint.activate([
            emptyState.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyState.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyState.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        emptyState.hide()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    @objc private func reload() {
        guard !loading else { return }
        loading = true
        Task { @MainActor in
            defer {
                loading = false
                refreshControl?.endRefreshing()
            }
            do {
                blocks = try await NativeAPIClient.listBlockedUsers()
                tableView.reloadData()
                if blocks.isEmpty {
                    emptyState.show(
                        symbol: "hand.raised",
                        title: String(localized: "Ninguém bloqueado"),
                        message: String(localized: "Pessoas que você bloquear aparecem aqui. Você pode desbloquear a qualquer momento.")
                    )
                } else {
                    emptyState.hide()
                }
            } catch {
                if blocks.isEmpty {
                    emptyState.show(
                        symbol: "exclamationmark.triangle",
                        title: String(localized: "Erro"),
                        message: error.localizedDescription
                    )
                }
                let alert = UIAlertController(title: String(localized: "Erro"), message: error.localizedDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
                present(alert, animated: true)
            }
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        blocks.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "blocked", for: indexPath)
        let person = blocks[indexPath.row]
        var config = UIListContentConfiguration.subtitleCell()
        config.text = person.displayName
        config.secondaryText = person.handle.isEmpty ? nil : "@\(person.handle)"
        config.image = UIImage(systemName: "hand.raised.fill")
        config.imageProperties.tintColor = KCDesign.danger
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        cell.kcApplyThemedGroupedCell()
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let person = blocks[indexPath.row]
        let sheet = UIAlertController(title: person.displayName, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: String(localized: "Desbloquear"), style: .destructive) { [weak self] _ in
            self?.unblock(person)
        })
        sheet.addAction(UIAlertAction(title: String(localized: "Cancelar"), style: .cancel))
        KCConfirmation.presentActionSheet(
            sheet,
            from: self,
            sourceView: tableView,
            sourceRect: tableView.rectForRow(at: indexPath)
        )
    }

    private func unblock(_ person: NativeAPIClient.BlockedPersonDTO) {
        Task { @MainActor in
            do {
                try await NativeAPIClient.unblockUser(userId: person.userId)
                blocks.removeAll { $0.userId == person.userId }
                tableView.reloadData()
                if blocks.isEmpty {
                    emptyState.show(
                        symbol: "hand.raised",
                        title: String(localized: "Ninguém bloqueado"),
                        message: String(localized: "Pessoas que você bloquear aparecem aqui. Você pode desbloquear a qualquer momento.")
                    )
                } else {
                    emptyState.hide()
                }
                KCToast.show(String(localized: "Usuário desbloqueado"), on: self)
            } catch {
                let alert = UIAlertController(title: String(localized: "Erro"), message: error.localizedDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
                present(alert, animated: true)
            }
        }
    }
}

/// Pure helpers for unit tests (reason catalog + copy).
enum ReportBlockLogic {
    static var reasonCodes: [String] {
        ReportBlockSupport.Reason.allCases.map(\.rawValue)
    }

    static func blockConfirmMessageContainsFriendshipHint(_ message: String) -> Bool {
        message.localizedCaseInsensitiveContains("amigo") || message.localizedCaseInsensitiveContains("friend")
    }
}
