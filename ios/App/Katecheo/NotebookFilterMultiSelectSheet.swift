import UIKit

/// Medium/large sheet: search + scrollable checklist for multi-select filters (tags or speakers).
@MainActor
final class NotebookFilterMultiSelectSheet: UIViewController, UITableViewDelegate, UITableViewDataSource, UISearchResultsUpdating {
    struct Item: Equatable {
        let id: String
        let title: String
    }

    var onDone: ((Set<String>) -> Void)?

    private let allItems: [Item]
    private var selected: Set<String>
    private var filtered: [Item] = []
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private let search = UISearchController(searchResultsController: nil)
    private let emptyLabel = UILabel()

    init(title: String, items: [Item], selected: Set<String>) {
        self.allItems = items
        self.selected = selected
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        KCChrome.styleScreen(view)
        if let nav = navigationController {
            KCChrome.applyNavigationBarAppearance(to: nav.navigationBar)
            nav.view.backgroundColor = KCDesign.screenBackground
        }

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: String(localized: "Limpar"),
            style: .plain,
            target: self,
            action: #selector(clearAll)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: String(localized: "Pronto"),
            style: .done,
            target: self,
            action: #selector(done)
        )
        navigationItem.leftBarButtonItem?.accessibilityIdentifier = "notebook.filter.clear"
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "notebook.filter.done"

        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = String(localized: "Buscar")
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true

        table.translatesAutoresizingMaskIntoConstraints = false
        KCChrome.styleGroupedTable(table)
        table.delegate = self
        table.dataSource = self
        table.register(KCThemedTableViewCell.self, forCellReuseIdentifier: "cell")
        table.allowsMultipleSelection = true
        table.keyboardDismissMode = .onDrag
        view.addSubview(table)

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.textAlignment = .center
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.font = KCDesign.rowSubtitle()
        emptyLabel.numberOfLines = 0
        emptyLabel.isHidden = true
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            table.topAnchor.constraint(equalTo: view.topAnchor),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.layoutMarginsGuide.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.layoutMarginsGuide.leadingAnchor),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.layoutMarginsGuide.trailingAnchor),
        ])

        applySearch("")
        refreshClearEnabled()
    }

    @objc private func clearAll() {
        selected.removeAll()
        table.reloadData()
        refreshClearEnabled()
        KCHaptics.selection()
    }

    @objc private func done() {
        onDone?(selected)
        dismiss(animated: true)
    }

    private func refreshClearEnabled() {
        navigationItem.leftBarButtonItem?.isEnabled = !selected.isEmpty
    }

    private func applySearch(_ raw: String) {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty {
            filtered = allItems
        } else {
            filtered = allItems.filter { $0.title.lowercased().contains(q) }
        }
        emptyLabel.text = String(localized: "Nenhum resultado")
        emptyLabel.isHidden = !filtered.isEmpty
        table.isHidden = filtered.isEmpty
        table.reloadData()
    }

    func updateSearchResults(for searchController: UISearchController) {
        applySearch(searchController.searchBar.text ?? "")
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        filtered.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let item = filtered[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = item.title
        config.textProperties.font = KCDesign.rowTitle()
        cell.contentConfiguration = config
        cell.accessoryType = selected.contains(item.id) ? .checkmark : .none
        cell.tintColor = KCDesign.accent
        cell.selectionStyle = .default
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = filtered[indexPath.row]
        if selected.contains(item.id) {
            selected.remove(item.id)
        } else {
            selected.insert(item.id)
        }
        tableView.reloadRows(at: [indexPath], with: .none)
        refreshClearEnabled()
        KCHaptics.selection()
    }
}
