import UIKit

/// Phase 2 native Grupos tab: list, create, open detail (notes via Caderno-style list).
final class GroupsListViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, UISearchResultsUpdating {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let refresh = UIRefreshControl()
    private var groups: [NativeAPIClient.GroupDTO] = []
    private var filtered: [NativeAPIClient.GroupDTO] = []
    private let search = UISearchController(searchResultsController: nil)
    private let emptyState = V2NEmptyStateView()
    private let statusBanner = V2NStatusBanner()

    override func viewDidLoad() {
        super.viewDidLoad()
        V2NChrome.styleCanvas(view)
        title = "Grupos"
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Novo grupo",
            style: .plain,
            target: self,
            action: #selector(createGroup)
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = "Novo grupo"

        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = "Pesquisar grupos"
        navigationItem.searchController = search
        definesPresentationContext = true

        tableView.translatesAutoresizingMaskIntoConstraints = false
        V2NChrome.styleGroupedTable(tableView)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(V2NGroupRowCell.self, forCellReuseIdentifier: V2NGroupRowCell.reuseId)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
        refresh.addTarget(self, action: #selector(reload), for: .valueChanged)
        tableView.refreshControl = refresh
        view.addSubview(tableView)
        view.addSubview(emptyState)
        view.addSubview(statusBanner)

        NSLayoutConstraint.activate([
            statusBanner.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: V2NDesign.Space.xxs),
            statusBanner.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            statusBanner.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),

            tableView.topAnchor.constraint(equalTo: statusBanner.bottomAnchor, constant: V2NDesign.Space.xxs),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyState.topAnchor.constraint(equalTo: statusBanner.bottomAnchor),
            emptyState.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyState.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyState.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])

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
            reload()
        }
    }

    @objc private func reload() {
        Task { @MainActor in
            defer { refresh.endRefreshing() }
            guard NativeAPIClient.hasBearer else {
                groups = []
                applyFilter()
                statusBanner.setStatus("Faça login para ver seus grupos.", kind: .warning)
                emptyState.show(
                    symbol: "person.2",
                    title: "Nenhum grupo ainda",
                    message: "Entre para sincronizar e criar grupos.",
                    actionTitle: "Entrar",
                    action: { [weak self] in self?.presentSignInTapped() }
                )
                tableView.isHidden = true
                return
            }
            do {
                groups = try await NativeAPIClient.listGroups()
                statusBanner.setStatus("\(groups.count) grupos · sincronizado", kind: .success)
                applyFilter()
            } catch NativeAPIClient.APIError.unauthorized {
                statusBanner.setStatus("Sessão expirada. Entre novamente.", kind: .error)
                groups = []
                applyFilter()
            } catch {
                statusBanner.setStatus("Sem rede. \(error.localizedDescription)", kind: .error)
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
                        title: "Você ainda não tem grupos",
                        message: "Crie um com «Novo grupo».",
                        actionTitle: "Novo grupo",
                        action: { [weak self] in self?.createGroup() }
                    )
                } else {
                    emptyState.show(symbol: "magnifyingglass", title: "Nenhum resultado", message: "Tente outro termo de busca.")
                }
            } else {
                emptyState.show(
                    symbol: "person.2",
                    title: "Nenhum grupo ainda",
                    message: "Entre para sincronizar e criar grupos.",
                    actionTitle: "Entrar",
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
        let cell = tableView.dequeueReusableCell(withIdentifier: V2NGroupRowCell.reuseId, for: indexPath) as! V2NGroupRowCell
        cell.configure(filtered[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        V2NHaptics.selection()
        let group = filtered[indexPath.row]
        let detail = NotebookListViewController(group: group)
        navigationController?.pushViewController(detail, animated: true)
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let group = filtered[indexPath.row]
        guard group.isAdmin else { return nil }
        let rename = UIContextualAction(style: .normal, title: "Renomear") { [weak self] _, _, done in
            self?.promptRename(group)
            done(true)
        }
        rename.backgroundColor = V2NDesign.accent
        let delete = UIContextualAction(style: .destructive, title: "Excluir") { [weak self] _, _, done in
            self?.confirmDelete(group) { done($0) }
        }
        return UISwipeActionsConfiguration(actions: [delete, rename])
    }

    @objc private func createGroup() {
        guard NativeAPIClient.hasBearer else {
            presentSignInTapped()
            return
        }
        V2NHaptics.light()
        let alert = UIAlertController(title: "Novo grupo", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "Nome do grupo"
            field.autocapitalizationType = .sentences
        }
        let listed = UIAlertAction(title: "Criar (listado)", style: .default) { [weak self] _ in
            self?.submitCreate(name: alert.textFields?.first?.text ?? "", visibility: "listed")
        }
        let priv = UIAlertAction(title: "Criar (privado)", style: .default) { [weak self] _ in
            self?.submitCreate(name: alert.textFields?.first?.text ?? "", visibility: "private")
        }
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
        alert.addAction(priv)
        alert.addAction(listed)
        present(alert, animated: true)
    }

    private func submitCreate(name: String, visibility: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            let err = UIAlertController(title: "Nome muito curto", message: "Use pelo menos 2 caracteres.", preferredStyle: .alert)
            err.addAction(UIAlertAction(title: "OK", style: .default))
            present(err, animated: true)
            return
        }
        Task { @MainActor in
            do {
                let group = try await NativeAPIClient.createGroup(name: trimmed, visibility: visibility)
                groups.insert(group, at: 0)
                applyFilter()
                V2NHaptics.success()
                let detail = NotebookListViewController(group: group)
                navigationController?.pushViewController(detail, animated: true)
            } catch {
                let err = UIAlertController(title: "Não foi possível criar", message: error.localizedDescription, preferredStyle: .alert)
                err.addAction(UIAlertAction(title: "OK", style: .default))
                present(err, animated: true)
            }
        }
    }

    private func promptRename(_ group: NativeAPIClient.GroupDTO) {
        let alert = UIAlertController(title: "Renomear grupo", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = group.name
            field.autocapitalizationType = .sentences
        }
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
        alert.addAction(UIAlertAction(title: "Salvar", style: .default) { [weak self] _ in
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
                V2NHaptics.success()
            } catch {
                let err = UIAlertController(title: "Erro", message: error.localizedDescription, preferredStyle: .alert)
                err.addAction(UIAlertAction(title: "OK", style: .default))
                present(err, animated: true)
            }
        }
    }

    private func confirmDelete(_ group: NativeAPIClient.GroupDTO, completion: @escaping (Bool) -> Void) {
        let alert = UIAlertController(
            title: "Excluir «\(group.name)»?",
            message: "Esta ação remove o grupo e as publicações. Não dá para desfazer.",
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { _ in completion(false) })
        alert.addAction(UIAlertAction(title: "Excluir grupo", style: .destructive) { [weak self] _ in
            Task { @MainActor in
                do {
                    try await NativeAPIClient.deleteGroup(id: group.id)
                    self?.groups.removeAll { $0.id == group.id }
                    self?.applyFilter()
                    completion(true)
                } catch {
                    completion(false)
                    let err = UIAlertController(title: "Erro", message: error.localizedDescription, preferredStyle: .alert)
                    err.addAction(UIAlertAction(title: "OK", style: .default))
                    self?.present(err, animated: true)
                }
            }
        })
        if let pop = alert.popoverPresentationController {
            pop.sourceView = tableView
            pop.sourceRect = tableView.bounds
        }
        present(alert, animated: true)
    }

    @objc private func presentSignInTapped() {
        let signIn = NativeSignInViewController()
        signIn.onSignedIn = { [weak self] in
            NotificationCenter.default.post(name: .nativeSessionDidChange, object: nil)
            self?.reload()
        }
        let nav = UINavigationController(rootViewController: signIn)
        V2NChrome.style(navigationController: nav)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }
}
