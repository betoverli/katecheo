import UIKit

/// Phase 4 native Versículos tab: book → chapter → verse picker + themes entry.
final class VersesHomeViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, UISearchResultsUpdating {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let refresh = UIRefreshControl()
    private let search = UISearchController(searchResultsController: nil)
    private let statusBanner = UILabel()

    private var books: [NativeAPIClient.BibleBookDTO] = []
    private var filtered: [NativeAPIClient.BibleBookDTO] = []
    private var prefs: NativeAPIClient.PrefsDTO?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Versículos"
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always

        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: "Temas", style: .plain, target: self, action: #selector(openThemes)),
            UIBarButtonItem(title: "Listas", style: .plain, target: self, action: #selector(openMyLists)),
        ]

        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = "Buscar livro"
        navigationItem.searchController = search
        definesPresentationContext = true

        statusBanner.translatesAutoresizingMaskIntoConstraints = false
        statusBanner.font = .preferredFont(forTextStyle: .caption1)
        statusBanner.textColor = .secondaryLabel
        statusBanner.textAlignment = .center
        statusBanner.numberOfLines = 2
        view.addSubview(statusBanner)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "book")
        refresh.addTarget(self, action: #selector(reload), for: .valueChanged)
        tableView.refreshControl = refresh
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            statusBanner.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            statusBanner.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            statusBanner.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),

            tableView.topAnchor.constraint(equalTo: statusBanner.bottomAnchor, constant: 4),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        _ = V2NGlassMaterial.sdkHasLiquidGlass()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task { @MainActor in
            if NativeAPIClient.hasBearer {
                _ = await NativeSessionBootstrap.migrateCookieToKeychainIfNeeded()
            }
            reload()
        }
    }

    @objc private func reload() {
        Task { @MainActor in
            defer { refresh.endRefreshing() }
            do {
                async let booksTask = NativeAPIClient.fetchBibleBooks(locale: "pt")
                if NativeAPIClient.hasBearer {
                    prefs = try? await NativeAPIClient.getPrefs()
                }
                books = try await booksTask
                let appName = ProfileBibleCatalog.name(for: prefs?.appId ?? "youversion")
                statusBanner.text = "\(books.count) livros · Bíblia: \(appName)"
                applyFilter()
            } catch {
                statusBanner.text = "Não foi possível carregar. \(error.localizedDescription)"
                applyFilter()
            }
        }
    }

    private func applyFilter() {
        let q = (search.searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty {
            filtered = books
        } else {
            filtered = books.filter {
                $0.name.lowercased().contains(q) || $0.abbr.lowercased().contains(q) || $0.id.lowercased().contains(q)
            }
        }
        tableView.reloadData()
    }

    func updateSearchResults(for searchController: UISearchController) {
        applyFilter()
    }

    private func books(in testament: String) -> [NativeAPIClient.BibleBookDTO] {
        filtered.filter { $0.testament == testament }
    }

    func numberOfSections(in tableView: UITableView) -> Int { 2 }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "Antigo Testamento" : "Novo Testamento"
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        books(in: section == 0 ? "ot" : "nt").count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "book", for: indexPath)
        let book = books(in: indexPath.section == 0 ? "ot" : "nt")[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = book.name
        config.secondaryText = "\(book.abbr) · \(book.chapters) capítulos"
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let book = books(in: indexPath.section == 0 ? "ot" : "nt")[indexPath.row]
        let chapters = VerseChapterViewController(book: book, prefs: prefs)
        navigationController?.pushViewController(chapters, animated: true)
    }

    @objc private func openThemes() {
        navigationController?.pushViewController(ThemesHomeViewController(prefs: prefs), animated: true)
    }

    @objc private func openMyLists() {
        navigationController?.pushViewController(MyCollectionsViewController(), animated: true)
    }
}
