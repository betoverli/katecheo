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

    private let emptyState = V2NEmptyStateView()

    override func viewDidLoad() {
        super.viewDidLoad()
        V2NChrome.styleCanvas(view)
        title = String(localized: "Versículos")
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always

        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: String(localized: "Temas"), style: .plain, target: self, action: #selector(openThemes)),
            UIBarButtonItem(title: String(localized: "Listas"), style: .plain, target: self, action: #selector(openMyLists)),
        ]

        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = String(localized: "Buscar livro")
        navigationItem.searchController = search
        definesPresentationContext = true

        statusBanner.translatesAutoresizingMaskIntoConstraints = false
        statusBanner.font = V2NDesign.caption()
        statusBanner.textColor = .secondaryLabel
        statusBanner.textAlignment = .center
        statusBanner.numberOfLines = 2
        statusBanner.adjustsFontForContentSizeCategory = true
        view.addSubview(statusBanner)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        V2NChrome.styleGroupedTable(tableView)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "book")
        refresh.addTarget(self, action: #selector(reload), for: .valueChanged)
        tableView.refreshControl = refresh
        view.addSubview(tableView)
        view.addSubview(emptyState)

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
                async let booksTask = NativeAPIClient.fetchBibleBooks(locale: AppLocale.apiCode)
                if NativeAPIClient.hasBearer {
                    prefs = try? await NativeAPIClient.getPrefs()
                }
                books = try await booksTask
                let appName = ProfileBibleCatalog.name(for: prefs?.appId ?? "youversion")
                statusBanner.text = String(localized: "\(books.count) livros · Bíblia: \(appName)")
                statusBanner.textColor = V2NDesign.accent
                applyFilter()
            } catch {
                statusBanner.text = String(localized: "Não foi possível carregar. \(error.localizedDescription)")
                statusBanner.textColor = V2NDesign.danger
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
        if filtered.isEmpty {
            tableView.isHidden = true
            if books.isEmpty {
                emptyState.show(
                    symbol: "book.closed",
                    title: String(localized: "Não foi possível carregar"),
                    message: String(localized: "Puxe para atualizar quando a rede voltar."),
                    actionTitle: String(localized: "Tentar de novo"),
                    action: { [weak self] in self?.reload() }
                )
            } else {
                emptyState.show(symbol: "magnifyingglass", title: String(localized: "Nenhum livro encontrado"), message: String(localized: "Tente outro nome ou abreviação."))
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

    private func books(in testament: String) -> [NativeAPIClient.BibleBookDTO] {
        filtered.filter { $0.testament == testament }
    }

    func numberOfSections(in tableView: UITableView) -> Int { 2 }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? String(localized: "Antigo Testamento") : String(localized: "Novo Testamento")
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        books(in: section == 0 ? "ot" : "nt").count
    }

    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        guard let header = view as? UITableViewHeaderFooterView else { return }
        header.textLabel?.font = V2NDesign.sectionHeader()
        header.textLabel?.textColor = .secondaryLabel
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "book", for: indexPath)
        let book = books(in: indexPath.section == 0 ? "ot" : "nt")[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = book.name
        config.textProperties.font = V2NDesign.rowTitle()
        config.secondaryText = String(localized: "\(book.abbr) · \(book.chapters) capítulos")
        config.secondaryTextProperties.font = V2NDesign.rowSubtitle()
        config.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = config
        cell.backgroundColor = V2NDesign.surface
        cell.accessoryType = .disclosureIndicator
        cell.accessibilityLabel = String(localized: "\(book.name), \(book.chapters) capítulos")
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        V2NHaptics.selection()
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
