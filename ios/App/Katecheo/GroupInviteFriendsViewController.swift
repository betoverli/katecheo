import UIKit

/// Multi-select friend picker to invite people into a notebook group.
final class GroupInviteFriendsViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, UISearchResultsUpdating {
    private let group: NativeAPIClient.GroupDTO
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let emptyState = KCEmptyStateView()
    private let search = UISearchController(searchResultsController: nil)
    private var friends: [NativeAPIClient.GroupInvitePersonDTO] = []
    private var selectedIds = Set<String>()
    private var searchWork: DispatchWorkItem?
    private var sending = false
    private lazy var sendButton = UIBarButtonItem(
        title: String(localized: "Enviar convites"),
        style: .done,
        target: self,
        action: #selector(sendInvites)
    )

    init(group: NativeAPIClient.GroupDTO) {
        self.group = group
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        KCChrome.styleScreen(view)
        title = String(localized: "Convidar amigos")
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = sendButton
        sendButton.isEnabled = false
        sendButton.accessibilityLabel = String(localized: "Enviar convites")

        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = String(localized: "Buscar amigos")
        search.searchBar.autocapitalizationType = .none
        search.searchBar.autocorrectionType = .no
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true

        tableView.translatesAutoresizingMaskIntoConstraints = false
        KCChrome.styleGroupedTable(tableView)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.allowsMultipleSelection = true
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "friend")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 56
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
        Task { await reload(query: currentQuery) }
    }

    private var currentQuery: String {
        (search.searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func reload(query: String) async {
        do {
            let list = try await NativeAPIClient.listGroupInviteFriends(groupId: group.id, query: query)
            await MainActor.run {
                self.friends = list
                self.selectedIds = self.selectedIds.intersection(Set(list.map(\.userId)))
                self.updateSendEnabled()
                self.tableView.reloadData()
                if list.isEmpty {
                    self.emptyState.show(
                        symbol: "person.2",
                        title: String(localized: "Nenhum amigo disponível"),
                        message: String(localized: "Só dá para convidar amigos que ainda não estão no grupo.")
                    )
                    self.tableView.isHidden = true
                } else {
                    self.emptyState.hide()
                    self.tableView.isHidden = false
                }
            }
        } catch {
            await MainActor.run {
                self.emptyState.show(
                    symbol: "person.2.slash",
                    title: String(localized: "Não foi possível carregar"),
                    message: error.localizedDescription,
                    actionTitle: String(localized: "Tentar de novo"),
                    action: { [weak self] in
                        guard let self else { return }
                        Task { await self.reload(query: self.currentQuery) }
                    }
                )
                self.tableView.isHidden = true
            }
        }
    }

    func updateSearchResults(for searchController: UISearchController) {
        searchWork?.cancel()
        let q = (searchController.searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let work = DispatchWorkItem { [weak self] in
            Task { await self?.reload(query: q) }
        }
        searchWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        friends.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "friend", for: indexPath)
        let friend = friends[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = friend.displayName
        config.secondaryText = friend.handle.isEmpty ? nil : "@\(friend.handle)"
        config.textProperties.font = KCDesign.rowTitle()
        config.secondaryTextProperties.font = KCDesign.caption()
        config.secondaryTextProperties.color = .secondaryLabel
        config.image = UIImage(systemName: "person.crop.circle.fill")
        config.imageProperties.tintColor = KCDesign.accent
        cell.contentConfiguration = config
        cell.backgroundColor = KCDesign.surface
        let selected = selectedIds.contains(friend.userId)
        cell.accessoryType = selected ? .checkmark : .none
        cell.tintColor = KCDesign.accent
        cell.selectionStyle = .default
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let friend = friends[indexPath.row]
        if selectedIds.contains(friend.userId) {
            selectedIds.remove(friend.userId)
        } else {
            selectedIds.insert(friend.userId)
        }
        tableView.reloadRows(at: [indexPath], with: .none)
        updateSendEnabled()
    }

    private func updateSendEnabled() {
        sendButton.isEnabled = !selectedIds.isEmpty && !sending
    }

    @objc private func sendInvites() {
        guard !selectedIds.isEmpty, !sending else { return }
        sending = true
        updateSendEnabled()
        let ids = Array(selectedIds)
        Task { @MainActor in
            defer {
                sending = false
                updateSendEnabled()
            }
            do {
                let invited = try await NativeAPIClient.createGroupInvites(groupId: group.id, userIds: ids)
                KCHaptics.success()
                let message: String
                if invited <= 0 {
                    message = String(localized: "Nenhum convite novo foi enviado.")
                } else if invited == 1 {
                    message = String(localized: "1 convite enviado.")
                } else {
                    message = String(format: String(localized: "%d convites enviados."), invited)
                }
                let alert = UIAlertController(title: String(localized: "Convites"), message: message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default) { [weak self] _ in
                    self?.navigationController?.popViewController(animated: true)
                })
                present(alert, animated: true)
            } catch {
                let alert = UIAlertController(
                    title: String(localized: "Erro"),
                    message: error.localizedDescription,
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
                present(alert, animated: true)
            }
        }
    }
}
