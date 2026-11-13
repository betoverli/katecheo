import UIKit

/// Phase 2 native Grupos tab: list, create, open detail (notes via Caderno-style list).
final class GroupsListViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, UISearchResultsUpdating {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let refresh = UIRefreshControl()
    private var groups: [NativeAPIClient.GroupDTO] = []
    private var filtered: [NativeAPIClient.GroupDTO] = []
    private let search = UISearchController(searchResultsController: nil)
    private let emptyState = KCEmptyStateView()
    private let statusBanner = KCStatusBanner()

    override func viewDidLoad() {
        super.viewDidLoad()
        KCChrome.styleScreen(view)
        title = String(localized: "Grupos")
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always
        if let nav = navigationController {
            KCChrome.style(navigationController: nav)
        }

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: String(localized: "Novo grupo"),
            style: .plain,
            target: self,
            action: #selector(createGroup)
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = String(localized: "Novo grupo")

        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = String(localized: "Pesquisar grupos")
        navigationItem.searchController = search
        definesPresentationContext = true

        tableView.translatesAutoresizingMaskIntoConstraints = false
        KCChrome.styleGroupedTable(tableView)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(KCGroupRowCell.self, forCellReuseIdentifier: KCGroupRowCell.reuseId)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
        refresh.addTarget(self, action: #selector(reload), for: .valueChanged)
        tableView.refreshControl = refresh
        view.addSubview(tableView)
        view.addSubview(emptyState)
        view.addSubview(statusBanner)

        NSLayoutConstraint.activate([
            statusBanner.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: KCDesign.Space.xxs),
            statusBanner.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            statusBanner.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),

            tableView.topAnchor.constraint(equalTo: statusBanner.bottomAnchor, constant: KCDesign.Space.xxs),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyState.topAnchor.constraint(equalTo: statusBanner.bottomAnchor),
            emptyState.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyState.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyState.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])

        // Offline-first paint from cache.
        if NativeAPIClient.hasBearer {
            groups = LocalSessionCache.loadGroups()
            applyFilter()
            if LocalSessionCache.showOfflineHint {
                statusBanner.setStatus(String(localized: "Offline — mostrando grupos em cache."), kind: .warning)
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reload),
            name: .nativeSessionDidChange,
            object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task { @MainActor in
            if !NativeAPIClient.hasBearer {
                _ = await NativeSessionBootstrap.migrateCookieToKeychainIfNeeded()
            }
            if NativeAPIClient.hasBearer, groups.isEmpty {
                groups = LocalSessionCache.loadGroups()
                applyFilter()
            }
            reload()
        }
    }

    @objc private func reload() {
        Task { @MainActor in
            defer { refresh.endRefreshing() }
            guard NativeAPIClient.hasBearer else {
                groups = []
                applyFilter()
                // Empty state carries the sign-in prompt — no persistent banner.
                statusBanner.setStatus(nil)
                emptyState.show(
                    symbol: "person.2",
                    title: String(localized: "Nenhum grupo ainda"),
                    message: String(localized: "Entre para sincronizar e criar grupos."),
                    actionTitle: String(localized: "Entrar"),
                    action: { [weak self] in self?.presentSignInTapped() }
                )
                tableView.isHidden = true
                return
            }
            if groups.isEmpty {
                groups = LocalSessionCache.loadGroups()
                applyFilter()
            }
            do {
                let force = refresh.isRefreshing
                groups = try await NativeAPIClient.listGroups(force: force)
                // Success: no persistent "sincronizado" banner (was leaking across screens).
                statusBanner.setStatus(nil)
                if !KatecheoScreenshotMode.isEnabled {
                    await refreshPendingActivityDots()
                }
                applyFilter()
            } catch NativeAPIClient.APIError.unauthorized {
                statusBanner.setStatus(String(localized: "Sessão expirada. Entre novamente."), kind: .error)
                groups = []
                applyFilter()
            } catch {
                // Keep cached groups — never treat network failure as logout.
                if groups.isEmpty {
                    groups = LocalSessionCache.loadGroups()
                }
                if KatecheoScreenshotMode.isEnabled {
                    statusBanner.setStatus(nil)
                } else {
                    LocalSessionCache.showOfflineHint = true
                    statusBanner.setStatus(String(localized: "Offline — mostrando grupos em cache."), kind: .warning)
                }
                applyFilter()
            }
        }
    }

    private func applyFilter() {
        let q = (search.searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty {
            filtered = groups
        } else {
            filtered = groups.filter {
                $0.name.lowercased().contains(q) || $0.description.lowercased().contains(q)
            }
        }
        if filtered.isEmpty {
            tableView.isHidden = true
            if NativeAPIClient.hasBearer {
                if q.isEmpty {
                    emptyState.show(
                        symbol: "person.3",
                        title: String(localized: "Você ainda não tem grupos"),
                        message: String(localized: "Crie um com «Novo grupo»."),
                        actionTitle: String(localized: "Novo grupo"),
                        action: { [weak self] in self?.createGroup() }
                    )
                } else {
                    emptyState.show(symbol: "magnifyingglass", title: String(localized: "Nenhum resultado"), message: String(localized: "Tente outro termo de busca."))
                }
            } else {
                emptyState.show(
                    symbol: "person.2",
                    title: String(localized: "Nenhum grupo ainda"),
                    message: String(localized: "Entre para sincronizar e criar grupos."),
                    actionTitle: String(localized: "Entrar"),
                    action: { [weak self] in self?.presentSignInTapped() }
                )
            }
        } else {
            emptyState.hide()
            tableView.isHidden = false
        }
        tableView.reloadData()
    }

    func updateSearchResults(for searchController: UISearchController) {
        applyFilter()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        filtered.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: KCGroupRowCell.reuseId, for: indexPath) as? KCGroupRowCell else {
            return UITableViewCell()
        }
        let group = filtered[indexPath.row]
        let unread = KCActivityStore.targetIds(kind: .groupActivity).contains(group.id)
            || KCActivityStore.targetIds(kind: .groupPending).contains(group.id)
        cell.configure(group, unread: unread)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        KCHaptics.selection()
        let group = filtered[indexPath.row]
        KCActivityStore.markGroupViewed(group.id)
        let detail = NotebookListViewController(group: group)
        navigationController?.pushViewController(detail, animated: true)
    }

    /// Admin groups: pending join requests are reachable in Membros — keep a groupPending dot.
    private func refreshPendingActivityDots() async {
        let adminGroups = groups.filter(\.isAdmin).prefix(12)
        for group in adminGroups {
            let members = (try? await NativeAPIClient.listGroupMembers(groupId: group.id)) ?? []
            let pending = members.filter(\.isPending).count
            KCActivityStore.reconcileGroupPending(groupId: group.id, pendingCount: pending)
        }
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let group = filtered[indexPath.row]
        guard group.isAdmin else { return nil }
        let rename = UIContextualAction.kcIconOnly(
            style: .normal,
            systemName: "pencil",
            accessibilityLabel: String(localized: "Renomear"),
            backgroundColor: KCDesign.accent
        ) { [weak self] _, _, done in
            self?.promptRename(group)
            done(true)
        }
        let delete = UIContextualAction.kcIconOnly(
            style: .destructive,
            systemName: "trash",
            accessibilityLabel: String(localized: "Excluir")
        ) { [weak self] _, view, done in
            self?.confirmDelete(group, from: view, at: indexPath) { done($0) }
        }
        return UISwipeActionsConfiguration(actions: [delete, rename])
    }

    @objc private func createGroup() {
        guard NativeAPIClient.hasBearer else {
            presentSignInTapped()
            return
        }
        KCHaptics.light()
        let alert = UIAlertController(title: String(localized: "Novo grupo"), message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = String(localized: "Nome do grupo")
            field.autocapitalizationType = .sentences
        }
        let listed = UIAlertAction(title: String(localized: "Criar (listado)"), style: .default) { [weak self] _ in
            self?.submitCreate(name: alert.textFields?.first?.text ?? "", visibility: "listed")
        }
        let priv = UIAlertAction(title: String(localized: "Criar (privado)"), style: .default) { [weak self] _ in
            self?.submitCreate(name: alert.textFields?.first?.text ?? "", visibility: "private")
        }
        alert.addAction(UIAlertAction(title: String(localized: "Cancelar"), style: .cancel))
        alert.addAction(priv)
        alert.addAction(listed)
        present(alert, animated: true)
    }

    private func submitCreate(name: String, visibility: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            let err = UIAlertController(title: String(localized: "Nome muito curto"), message: String(localized: "Use pelo menos 2 caracteres."), preferredStyle: .alert)
            err.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
            present(err, animated: true)
            return
        }
        Task { @MainActor in
            do {
                let group = try await NativeAPIClient.createGroup(name: trimmed, visibility: visibility)
                groups.insert(group, at: 0)
                applyFilter()
                KCHaptics.success()
                let detail = NotebookListViewController(group: group)
                navigationController?.pushViewController(detail, animated: true)
            } catch {
                let err = UIAlertController(title: String(localized: "Não foi possível criar"), message: error.localizedDescription, preferredStyle: .alert)
                err.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
                present(err, animated: true)
            }
        }
    }

    private func promptRename(_ group: NativeAPIClient.GroupDTO) {
        let alert = UIAlertController(title: String(localized: "Renomear grupo"), message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = group.name
            field.autocapitalizationType = .sentences
        }
        alert.addAction(UIAlertAction(title: String(localized: "Cancelar"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "Salvar"), style: .default) { [weak self] _ in
            let name = alert.textFields?.first?.text ?? ""
            self?.rename(group, to: name)
        })
        present(alert, animated: true)
    }

    private func rename(_ group: NativeAPIClient.GroupDTO, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return }
        Task { @MainActor in
            do {
                let updated = try await NativeAPIClient.updateGroup(id: group.id, name: trimmed)
                if let idx = groups.firstIndex(where: { $0.id == group.id }) {
                    groups[idx] = updated
                }
                applyFilter()
                KCHaptics.success()
            } catch {
                let err = UIAlertController(title: String(localized: "Erro"), message: error.localizedDescription, preferredStyle: .alert)
                err.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
                present(err, animated: true)
            }
        }
    }

    private func confirmDelete(
        _ group: NativeAPIClient.GroupDTO,
        from source: UIView?,
        at indexPath: IndexPath,
        completion: @escaping (Bool) -> Void
    ) {
        let alert = UIAlertController(
            title: String(localized: "Excluir «\(group.name)»?"),
            message: String(localized: "Esta ação remove o grupo e as publicações. Não dá para desfazer."),
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: String(localized: "Cancelar"), style: .cancel) { _ in completion(false) })
        alert.addAction(UIAlertAction(title: String(localized: "Excluir grupo"), style: .destructive) { [weak self] _ in
            Task { @MainActor in
                do {
                    try await NativeAPIClient.deleteGroup(id: group.id)
                    self?.groups.removeAll { $0.id == group.id }
                    self?.applyFilter()
                    completion(true)
                } catch {
                    completion(false)
                    let err = UIAlertController(title: String(localized: "Erro"), message: error.localizedDescription, preferredStyle: .alert)
                    err.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
                    self?.present(err, animated: true)
                }
            }
        })
        if let source {
            KCConfirmation.presentActionSheet(alert, from: self, sourceView: source, sourceRect: source.bounds)
        } else {
            KCConfirmation.presentActionSheet(
                alert,
                from: self,
                sourceView: tableView,
                sourceRect: tableView.rectForRow(at: indexPath)
            )
        }
    }

    @objc private func presentSignInTapped() {
        let signIn = NativeSignInViewController()
        signIn.onSignedIn = { [weak self] in
            NotificationCenter.default.post(name: .nativeSessionDidChange, object: nil)
            self?.reload()
        }
        let nav = UINavigationController(rootViewController: signIn)
        KCChrome.style(navigationController: nav)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }
}
