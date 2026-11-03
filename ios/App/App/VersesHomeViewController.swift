import UIKit

/// Native Versículos tab: book picker (names ↔ siglas), Temas / Listas chips, deferred search.
final class VersesHomeViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource, UISearchResultsUpdating {
    private enum HomeFilter: String {
        case books = "books"
        case themes = "themes"
        case lists = "lists"
    }

    private let chips = V2NFilterChipsView()
    private let modeToggle = V2NModeToggle()
    private let statusBanner = UILabel()
    private let emptyState = V2NEmptyStateView()
    private var collectionView: UICollectionView!
    private let search = UISearchController(searchResultsController: nil)

    private var books: [NativeAPIClient.BibleBookDTO] = []
    private var filtered: [NativeAPIClient.BibleBookDTO] = []
    private var prefs: NativeAPIClient.PrefsDTO?
    private var booksCompact = false
    private var homeFilter: HomeFilter = .books
    private var searchVisible = false

    private var otBooks: [NativeAPIClient.BibleBookDTO] { filtered.filter { $0.testament == "ot" } }
    private var ntBooks: [NativeAPIClient.BibleBookDTO] { filtered.filter { $0.testament == "nt" } }

    override func viewDidLoad() {
        super.viewDidLoad()
        V2NChrome.styleCanvas(view)
        title = String(localized: "Versículos")
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always

        booksCompact = UserDefaults.standard.bool(forKey: "v2n.booksCompact")
        modeToggle.setCompact(booksCompact)
        modeToggle.onChange = { [weak self] compact in
            self?.booksCompact = compact
            UserDefaults.standard.set(compact, forKey: "v2n.booksCompact")
            if NativeAPIClient.hasBearer {
                Task { try? await NativeAPIClient.patchPrefs(["booksCompact": compact]) }
            }
            self?.rebuildLayout()
        }

        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = String(localized: "Buscar livro")
        definesPresentationContext = true
        // Search stays off the chrome until the magnifying-glass is tapped.
        navigationItem.searchController = nil
        navigationItem.hidesSearchBarWhenScrolling = true

        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(image: UIImage(systemName: "magnifyingglass"), style: .plain, target: self, action: #selector(toggleSearch)),
        ]
        navigationItem.rightBarButtonItem?.accessibilityLabel = String(localized: "Buscar")

        chips.configure(
            chips: [
                V2NFilterChip(id: HomeFilter.books.rawValue, title: String(localized: "Livros"), systemImage: "book"),
                V2NFilterChip(id: HomeFilter.themes.rawValue, title: String(localized: "Temas"), systemImage: "tag"),
                V2NFilterChip(id: HomeFilter.lists.rawValue, title: String(localized: "Listas"), systemImage: "bookmark"),
            ],
            selectedId: HomeFilter.books.rawValue
        )
        chips.onSelect = { [weak self] id in
            self?.selectFilter(id)
        }

        statusBanner.translatesAutoresizingMaskIntoConstraints = false
        statusBanner.font = V2NDesign.caption()
        statusBanner.textColor = .secondaryLabel
        statusBanner.textAlignment = .center
        statusBanner.numberOfLines = 2
        statusBanner.adjustsFontForContentSizeCategory = true

        let layout = V2NBookGridLayout.make(compact: booksCompact)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.alwaysBounceVertical = true
        collectionView.register(V2NBookNameCell.self, forCellWithReuseIdentifier: V2NBookNameCell.reuseId)
        collectionView.register(V2NBookAbbrCell.self, forCellWithReuseIdentifier: V2NBookAbbrCell.reuseId)
        collectionView.register(
            V2NBookSectionHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: V2NBookSectionHeaderView.reuseId
        )
        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(reload), for: .valueChanged)
        collectionView.refreshControl = refresh

        view.addSubview(chips)
        view.addSubview(modeToggle)
        view.addSubview(statusBanner)
        view.addSubview(collectionView)
        view.addSubview(emptyState)

        NSLayoutConstraint.activate([
            chips.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: V2NDesign.Space.xxs),
            chips.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chips.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            modeToggle.topAnchor.constraint(equalTo: chips.bottomAnchor, constant: V2NDesign.Space.xs),
            modeToggle.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            modeToggle.leadingAnchor.constraint(greaterThanOrEqualTo: view.layoutMarginsGuide.leadingAnchor),

            statusBanner.topAnchor.constraint(equalTo: modeToggle.bottomAnchor, constant: V2NDesign.Space.xxs),
            statusBanner.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            statusBanner.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),

            collectionView.topAnchor.constraint(equalTo: statusBanner.bottomAnchor, constant: V2NDesign.Space.xs),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyState.topAnchor.constraint(equalTo: statusBanner.bottomAnchor),
            emptyState.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyState.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyState.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])

        _ = V2NGlassMaterial.sdkHasLiquidGlass()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if homeFilter != .books {
            chips.setSelected(HomeFilter.books.rawValue)
            homeFilter = .books
            updateChromeForFilter()
        }
        Task { @MainActor in
            if NativeAPIClient.hasBearer {
                _ = await NativeSessionBootstrap.migrateCookieToKeychainIfNeeded()
            }
            reload()
        }
    }

    @objc private func toggleSearch() {
        searchVisible.toggle()
        if searchVisible {
            navigationItem.searchController = search
            DispatchQueue.main.async { [weak self] in
                self?.search.isActive = true
                self?.search.searchBar.becomeFirstResponder()
            }
        } else {
            search.isActive = false
            search.searchBar.text = nil
            navigationItem.searchController = nil
            applyFilter()
        }
    }

    private func selectFilter(_ id: String) {
        guard let filter = HomeFilter(rawValue: id) else { return }
        homeFilter = filter
        updateChromeForFilter()
        switch filter {
        case .books:
            break
        case .themes:
            navigationController?.pushViewController(ThemesHomeViewController(prefs: prefs), animated: true)
        case .lists:
            navigationController?.pushViewController(MyCollectionsViewController(), animated: true)
        }
    }

    private func updateChromeForFilter() {
        let showBooks = homeFilter == .books
        modeToggle.isHidden = !showBooks
        collectionView.isHidden = !showBooks
        if !showBooks {
            emptyState.hide()
        }
    }

    @objc private func reload() {
        Task { @MainActor in
            defer { collectionView.refreshControl?.endRefreshing() }
            do {
                async let booksTask = NativeAPIClient.fetchBibleBooks(locale: AppLocale.apiCode)
                if NativeAPIClient.hasBearer {
                    prefs = try? await NativeAPIClient.getPrefs()
                    if let prefs {
                        booksCompact = prefs.booksCompact
                        modeToggle.setCompact(booksCompact)
                        UserDefaults.standard.set(booksCompact, forKey: "v2n.booksCompact")
                    }
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
            collectionView.isHidden = true
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
            collectionView.isHidden = homeFilter != .books
        }
        collectionView.reloadData()
    }

    func updateSearchResults(for searchController: UISearchController) {
        applyFilter()
    }

    private func rebuildLayout() {
        collectionView.setCollectionViewLayout(V2NBookGridLayout.make(compact: booksCompact), animated: true)
        collectionView.reloadData()
    }

    // MARK: - Collection

    func numberOfSections(in collectionView: UICollectionView) -> Int { 2 }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        section == 0 ? otBooks.count : ntBooks.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let book = (indexPath.section == 0 ? otBooks : ntBooks)[indexPath.item]
        if booksCompact {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: V2NBookAbbrCell.reuseId, for: indexPath) as! V2NBookAbbrCell
            cell.configure(abbr: book.abbr, accessibilityName: book.name)
            return cell
        }
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: V2NBookNameCell.reuseId, for: indexPath) as! V2NBookNameCell
        cell.configure(name: book.name, abbr: book.abbr)
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind,
            withReuseIdentifier: V2NBookSectionHeaderView.reuseId,
            for: indexPath
        ) as! V2NBookSectionHeaderView
        header.configure(
            title: indexPath.section == 0
                ? String(localized: "Antigo Testamento")
                : String(localized: "Novo Testamento")
        )
        return header
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        V2NHaptics.selection()
        let book = (indexPath.section == 0 ? otBooks : ntBooks)[indexPath.item]
        navigationController?.pushViewController(VerseChapterViewController(book: book, prefs: prefs), animated: true)
    }
}
