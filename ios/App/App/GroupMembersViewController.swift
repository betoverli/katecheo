import UIKit

/// Group members management (invite share, accept/decline, role, remove) — opened from the group `…` menu.
final class GroupMembersViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    private let group: NativeAPIClient.GroupDTO
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let refresh = UIRefreshControl()
    private let emptyState = V2NEmptyStateView()
    private var members: [NativeAPIClient.GroupMemberDTO] = []
    private var meId: String?

    private var pending: [NativeAPIClient.GroupMemberDTO] { members.filter(\.isPending) }
    private var accepted: [NativeAPIClient.GroupMemberDTO] { members.filter { !$0.isPending } }

    init(group: NativeAPIClient.GroupDTO) {
        self.group = group
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        V2NChrome.styleScreen(view)
        title = String(localized: "Membros")
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: String(localized: "Convidar"),
            style: .plain,
            target: self,
            action: #selector(invite)
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = String(localized: "Convidar")

        tableView.translatesAutoresizingMaskIntoConstraints = false
        V2NChrome.styleGroupedTable(tableView)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "member")
        refresh.addTarget(self, action: #selector(reload), for: .valueChanged)
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
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    @objc private func reload() {
        Task { @MainActor in
            defer { refresh.endRefreshing() }
            do {
                if meId == nil {
                    meId = try? await NativeAPIClient.getMe().id
                }
                members = try await NativeAPIClient.listGroupMembers(groupId: group.id)
                V2NActivityStore.reconcileGroupPending(groupId: group.id, pendingCount: pending.count)
                emptyState.hide()
                tableView.isHidden = false
                tableView.reloadData()
            } catch {
                if members.isEmpty {
                    emptyState.show(
                        symbol: "person.2.slash",
                        title: String(localized: "Não foi possível carregar"),
                        message: error.localizedDescription,
                        actionTitle: String(localized: "Tentar de novo"),
                        action: { [weak self] in self?.reload() }
                    )
                    tableView.isHidden = true
                } else {
                    let alert = UIAlertController(title: String(localized: "Erro"), message: error.localizedDescription, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
                    present(alert, animated: true)
                }
            }
        }
    }

    @objc private func invite() {
        let url = NativeAPIClient.baseURL.appendingPathComponent("groups/\(group.id)")
        let text = String(format: String(localized: "Entre no grupo «%@» no Katecheo"), group.name)
        let vc = UIActivityViewController(activityItems: [text, url], applicationActivities: nil)
        if let pop = vc.popoverPresentationController {
            pop.barButtonItem = navigationItem.rightBarButtonItem
        }
        present(vc, animated: true)
    }

    private var sectionCount: Int {
        (group.isAdmin && !pending.isEmpty ? 1 : 0) + (accepted.isEmpty ? 0 : 1)
    }

    private func members(in section: Int) -> [NativeAPIClient.GroupMemberDTO] {
        if group.isAdmin && !pending.isEmpty {
            return section == 0 ? pending : accepted
        }
        return accepted
    }

    private func title(for section: Int) -> String? {
        if group.isAdmin && !pending.isEmpty {
            return section == 0 ? String(localized: "Pedidos") : String(localized: "Membros")
        }
        return nil
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        max(sectionCount, 1)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let rows = members(in: section)
        return rows.isEmpty ? 0 : rows.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        title(for: section)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "member", for: indexPath)
        let member = members(in: indexPath.section)[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = member.displayName
        config.secondaryText = {
            var parts: [String] = []
            if !member.handle.isEmpty { parts.append("@\(member.handle)") }
            if member.isAdmin { parts.append(String(localized: "admin")) }
            if member.isPending { parts.append(String(localized: "pendente")) }
            return parts.joined(separator: " · ")
        }()
        config.textProperties.font = V2NDesign.rowTitle()
        config.secondaryTextProperties.font = V2NDesign.caption()
        config.secondaryTextProperties.color = .secondaryLabel
        config.image = UIImage(systemName: "person.crop.circle.fill")
        config.imageProperties.tintColor = V2NDesign.accent
        cell.contentConfiguration = config
        cell.backgroundColor = V2NDesign.surface
        cell.accessoryType = canManage(member) ? .disclosureIndicator : .none
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let member = members(in: indexPath.section)[indexPath.row]
        presentActions(for: member)
    }

    private func canManage(_ member: NativeAPIClient.GroupMemberDTO) -> Bool {
        if member.isPending { return group.isAdmin }
        if member.userId == meId { return true }
        return group.isAdmin && member.userId != meId
    }

    private func presentActions(for member: NativeAPIClient.GroupMemberDTO) {
        guard canManage(member) else { return }
        let sheet = UIAlertController(title: member.displayName, message: nil, preferredStyle: .actionSheet)
        if member.isPending, group.isAdmin {
            sheet.addAction(UIAlertAction(title: String(localized: "Aceitar"), style: .default) { [weak self] _ in
                self?.decide(member, accept: true)
            })
            sheet.addAction(UIAlertAction(title: String(localized: "Recusar"), style: .destructive) { [weak self] _ in
                self?.decide(member, accept: false)
            })
        } else if group.isAdmin, member.userId != meId {
            let roleTitle = member.isAdmin
                ? String(localized: "Tornar membro")
                : String(localized: "Tornar admin")
            sheet.addAction(UIAlertAction(title: roleTitle, style: .default) { [weak self] _ in
                self?.setRole(member, role: member.isAdmin ? "member" : "admin")
            })
            sheet.addAction(UIAlertAction(title: String(localized: "Remover do grupo"), style: .destructive) { [weak self] _ in
                self?.remove(member)
            })
        } else if member.userId == meId {
            sheet.addAction(UIAlertAction(title: String(localized: "Sair do grupo"), style: .destructive) { [weak self] _ in
                self?.remove(member)
            })
        }
        sheet.addAction(UIAlertAction(title: String(localized: "Cancelar"), style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = tableView
            pop.sourceRect = tableView.bounds
        }
        present(sheet, animated: true)
    }

    private func decide(_ member: NativeAPIClient.GroupMemberDTO, accept: Bool) {
        Task { @MainActor in
            do {
                try await NativeAPIClient.decideGroupMember(groupId: group.id, userId: member.userId, accept: accept)
                V2NHaptics.success()
                reload()
            } catch {
                presentError(error)
            }
        }
    }

    private func setRole(_ member: NativeAPIClient.GroupMemberDTO, role: String) {
        Task { @MainActor in
            do {
                try await NativeAPIClient.setGroupMemberRole(groupId: group.id, userId: member.userId, role: role)
                V2NHaptics.success()
                reload()
            } catch {
                presentError(error)
            }
        }
    }

    private func remove(_ member: NativeAPIClient.GroupMemberDTO) {
        Task { @MainActor in
            do {
                try await NativeAPIClient.removeGroupMember(groupId: group.id, userId: member.userId)
                V2NHaptics.medium()
                if member.userId == meId {
                    navigationController?.popToRootViewController(animated: true)
                } else {
                    reload()
                }
            } catch {
                presentError(error)
            }
        }
    }

    private func presentError(_ error: Error) {
        let alert = UIAlertController(title: String(localized: "Erro"), message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
        present(alert, animated: true)
    }
}
