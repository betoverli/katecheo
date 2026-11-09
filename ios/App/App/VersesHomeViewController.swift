import UIKit

/// Ferramentas (Tools) tab: shared pills switch embedded content in place.
/// Opens on the last-used pill (UserDefaults) or Livros by default — no cards hub.
final class VersesHomeViewController: UIViewController, UISearchResultsUpdating {
    private enum Tool: String, CaseIterable {
        case books, themes, lists, reading

        var title: String {
            switch self {
            case .books: return String(localized: "Livros")
            case .themes: return String(localized: "Temas")
            case .lists: return String(localized: "Listas")
            case .reading: return String(localized: "Leitura")
            }
        }

        var symbol: String {
            switch self {
            case .books: return "book"
            case .themes: return "tag"
            case .lists: return "bookmark"
            case .reading: return "calendar"
            }
        }
    }

    private static let lastToolKey = "v2n.ferramentas.lastTool"

    private let chips = V2NFilterChipsView()
    private let contentHost = UIView()
    private var prefs: NativeAPIClient.PrefsDTO?
    private var selectedTool: Tool = .books

    private lazy var booksVC = BooksHomeViewController(prefs: nil, embedded: true)
    private lazy var themesVC = ThemesHomeViewController(prefs: nil, embedded: true)
    private lazy var listsVC = MyCollectionsViewController(embedded: true)
    private lazy var readingVC = ReadingHomeViewController(embedded: true)

    override func viewDidLoad() {
        super.viewDidLoad()
        V2NChrome.styleScreen(view)
        title = String(localized: "Ferramentas")
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always
        definesPresentationContext = true
        if let nav = navigationController {
            V2NChrome.style(navigationController: nav)
        }

        let initial = restoredTool()
        selectedTool = initial
        // Always keep one pill selected — no cards fallback.
        chips.allowsDeselect = false
        chips.configure(
            chips: Tool.allCases.map { V2NFilterChip(id: $0.rawValue, title: $0.title, systemImage: $0.symbol) },
            selectedId: initial.rawValue,
            badgedIds: V2NActivityStore.readingChipDot ? ["reading"] : []
        )
        chips.onSelect = { [weak self] id in
            guard let id, let tool = Tool(rawValue: id) else { return }
            self?.selectTool(tool, animated: true)
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshReadingChipDot),
            name: V2NActivityStore.didChangeNotification,
            object: nil
        )

        contentHost.translatesAutoresizingMaskIntoConstraints = false
        contentHost.backgroundColor = V2NDesign.screenBackground

        view.addSubview(chips)
        view.addSubview(contentHost)

        NSLayoutConstraint.activate([
            chips.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: V2NDesign.Space.xxs),
            chips.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chips.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            contentHost.topAnchor.constraint(equalTo: chips.bottomAnchor, constant: V2NDesign.Space.xxs),
            contentHost.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentHost.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentHost.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        embedChild(booksVC)
        embedChild(themesVC)
        embedChild(listsVC)
        embedChild(readingVC)
        selectTool(initial, animated: false)

        _ = V2NGlassMaterial.sdkHasLiquidGlass()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always
        Task { @MainActor in
            if NativeAPIClient.hasBearer {
                // SWR — skip network when prefs TTL still fresh.
                prefs = try? await NativeAPIClient.getPrefs(force: false)
                booksVC.updatePrefs(prefs)
            }
            refreshSelectedEmbedded()
        }
    }

    /// Deep links / parent chrome: select the matching Tools pill (embedded, not a push).
    func selectHomeFilter(_ id: String) {
        guard let tool = Tool(rawValue: id) else { return }
        chips.setSelected(tool.rawValue, animated: false)
        selectTool(tool, animated: false)
    }

    private func restoredTool() -> Tool {
        if let raw = UserDefaults.standard.string(forKey: Self.lastToolKey),
           let tool = Tool(rawValue: raw)
        {
            return tool
        }
        return .books
    }

    private func persistTool(_ tool: Tool) {
        UserDefaults.standard.set(tool.rawValue, forKey: Self.lastToolKey)
    }

    private func embedChild(_ child: UIViewController) {
        addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        contentHost.addSubview(child.view)
        NSLayoutConstraint.activate([
            child.view.topAnchor.constraint(equalTo: contentHost.topAnchor),
            child.view.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
            child.view.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor),
        ])
        child.didMove(toParent: self)
        child.view.isHidden = true
    }

    private func hideEmbeddedTools() {
        booksVC.view.isHidden = true
        themesVC.view.isHidden = true
        listsVC.view.isHidden = true
        readingVC.view.isHidden = true
    }

    private func selectTool(_ tool: Tool, animated: Bool) {
        selectedTool = tool
        persistTool(tool)
        let apply = {
            self.hideEmbeddedTools()
            switch tool {
            case .books:
                self.booksVC.view.isHidden = false
                self.booksVC.reloadFromParent()
            case .themes:
                self.themesVC.view.isHidden = false
                self.themesVC.reloadFromParent()
            case .lists:
                self.listsVC.view.isHidden = false
                self.listsVC.reloadFromParent()
            case .reading:
                self.readingVC.view.isHidden = false
                self.readingVC.reloadFromParent()
            }
            self.installSearchController(for: tool)
        }
        if animated {
            UIView.transition(with: contentHost, duration: 0.22, options: [.transitionCrossDissolve, .allowUserInteraction], animations: apply)
        } else {
            apply()
        }
    }

    private func refreshSelectedEmbedded() {
        switch selectedTool {
        case .books: booksVC.reloadFromParent()
        case .themes: themesVC.reloadFromParent()
        case .lists: listsVC.reloadFromParent()
        case .reading: readingVC.reloadFromParent()
        }
        installSearchController(for: selectedTool)
    }

    /// Temas / Leitura: search collapses until pull-down (same as Caderno). Livros / Listas: none.
    private func installSearchController(for tool: Tool) {
        switch tool {
        case .themes:
            let sc = themesVC.parentSearchController
            sc.searchResultsUpdater = self
            sc.obscuresBackgroundDuringPresentation = false
            sc.searchBar.placeholder = String(localized: "Buscar temas")
            sc.searchBar.tintColor = V2NDesign.accent
            navigationItem.searchController = sc
            navigationItem.hidesSearchBarWhenScrolling = true
        case .reading:
            let sc = readingVC.parentSearchController
            sc.searchResultsUpdater = self
            sc.obscuresBackgroundDuringPresentation = false
            sc.searchBar.placeholder = String(localized: "Buscar planos")
            sc.searchBar.tintColor = V2NDesign.accent
            navigationItem.searchController = sc
            navigationItem.hidesSearchBarWhenScrolling = true
        case .books, .lists:
            navigationItem.searchController = nil
        }
    }

    func updateSearchResults(for searchController: UISearchController) {
        let q = searchController.searchBar.text ?? ""
        switch selectedTool {
        case .themes: themesVC.applyParentSearchQuery(q)
        case .reading: readingVC.applyParentSearchQuery(q)
        case .books, .lists: break
        }
    }

    @objc private func refreshReadingChipDot() {
        chips.setBadgedIds(V2NActivityStore.readingChipDot ? ["reading"] : [])
    }
}

// MARK: - Books grid (formerly Versículos home content)

/// Book picker with OT/NT sections and Siglas/Nomes toggle on the OT header.
final class BooksHomeViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource {
    private let modeToggle = V2NModeToggle()
    private let emptyState = V2NEmptyStateView()
    private var collectionView: UICollectionView!
    private let embedded: Bool

    private var books: [NativeAPIClient.BibleBookDTO] = []
    private var filtered: [NativeAPIClient.BibleBookDTO] = []
    private var prefs: NativeAPIClient.PrefsDTO?
    private var booksCompact = false
    private var booksLoadToken = 0
    private var pendingLayoutRefresh = false

    private var otBooks: [NativeAPIClient.BibleBookDTO] { filtered.filter { $0.testament == "ot" } }
    private var ntBooks: [NativeAPIClient.BibleBookDTO] { filtered.filter { $0.testament == "nt" } }

    init(prefs: NativeAPIClient.PrefsDTO?, embedded: Bool = false) {
        self.prefs = prefs
        self.embedded = embedded
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        V2NChrome.styleScreen(view)
        if embedded {
            title = nil
            navigationItem.largeTitleDisplayMode = .never
        } else {
            title = String(localized: "Livros")
            navigationItem.largeTitleDisplayMode = .always
            navigationController?.navigationBar.prefersLargeTitles = true
        }

        applyBooksCompact(resolvedInitialBooksCompact(), rebuild: false)
        modeToggle.onChange = { [weak self] compact in
            self?.applyBooksCompact(compact, rebuild: true)
            if NativeAPIClient.hasBearer {
                Task { try? await NativeAPIClient.patchPrefs(["booksCompact": compact]) }
            }
        }

        let layout = V2NBookGridLayout.make(isCompact: { [weak self] in
            self?.booksCompact ?? false
        })
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

        view.addSubview(collectionView)
        view.addSubview(emptyState)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyState.topAnchor.constraint(equalTo: view.topAnchor),
            emptyState.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyState.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyState.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !embedded {
            navigationController?.navigationBar.prefersLargeTitles = true
            navigationItem.largeTitleDisplayMode = .always
        }
        reload()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if pendingLayoutRefresh, collectionView.bounds.width > 1 {
            refreshCollectionLayoutIfNeeded(force: true)
        }
    }

    func updatePrefs(_ prefs: NativeAPIClient.PrefsDTO?) {
        self.prefs = prefs
        if isViewLoaded {
            applyBooksCompact(resolvedInitialBooksCompact(), rebuild: true)
        }
    }

    func reloadFromParent() {
        guard isViewLoaded else { return }
        reload()
    }

    private func resolvedInitialBooksCompact() -> Bool {
        if let prefs { return prefs.booksCompact }
        if UserDefaults.standard.object(forKey: "v2n.booksCompact") != nil {
            return UserDefaults.standard.bool(forKey: "v2n.booksCompact")
        }
        return false
    }

    private func applyBooksCompact(_ compact: Bool, rebuild: Bool) {
        booksCompact = compact
        modeToggle.setCompact(compact)
        UserDefaults.standard.set(compact, forKey: "v2n.booksCompact")
        if rebuild {
            refreshCollectionLayoutIfNeeded(force: true)
        }
    }

    private func refreshCollectionLayoutIfNeeded(force: Bool) {
        guard collectionView != nil else { return }
        if collectionView.bounds.width <= 1 {
            pendingLayoutRefresh = true
            return
        }
        pendingLayoutRefresh = false
        collectionView.collectionViewLayout.invalidateLayout()
        if force {
            collectionView.reloadData()
        }
    }

    @objc private func reload() {
        booksLoadToken += 1
        let token = booksLoadToken
        Task { @MainActor in
            defer { collectionView.refreshControl?.endRefreshing() }
            do {
                let forceNetwork = collectionView.refreshControl?.isRefreshing == true
                // Instant paint from disk / prior day cache before any network.
                if books.isEmpty, let cached = NativeSWR.loadBibleBooks(locale: AppLocale.apiCode) {
                    books = cached
                    applyFilter()
                }
                async let booksTask = NativeAPIClient.fetchBibleBooks(
                    locale: AppLocale.apiCode,
                    force: forceNetwork
                )
                if NativeAPIClient.hasBearer {
                    prefs = try? await NativeAPIClient.getPrefs(force: forceNetwork)
                    if let prefs {
                        applyBooksCompact(prefs.booksCompact, rebuild: false)
                    }
                }
                let loaded = try await booksTask
                guard token == booksLoadToken else { return }
                books = loaded
                applyFilter()
                refreshCollectionLayoutIfNeeded(force: true)
            } catch {
                guard token == booksLoadToken else { return }
                if books.isEmpty, let cached = NativeSWR.loadBibleBooks(locale: AppLocale.apiCode) {
                    books = cached
                }
                applyFilter()
            }
        }
    }

    private func applyFilter() {
        filtered = books
        if filtered.isEmpty {
            collectionView.isHidden = true
            emptyState.show(
                symbol: "book.closed",
                title: String(localized: "Não foi possível carregar"),
                message: String(localized: "Puxe para atualizar quando a rede voltar."),
                actionTitle: String(localized: "Tentar de novo"),
                action: { [weak self] in self?.reload() }
            )
        } else {
            emptyState.hide()
            collectionView.isHidden = false
        }
        collectionView.reloadData()
    }

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
                : String(localized: "Novo Testamento"),
            trailing: indexPath.section == 0 ? modeToggle : nil
        )
        return header
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        V2NHaptics.selection()
        let book = (indexPath.section == 0 ? otBooks : ntBooks)[indexPath.item]
        navigationController?.pushViewController(VerseChapterViewController(book: book, prefs: prefs), animated: true)
    }
}
