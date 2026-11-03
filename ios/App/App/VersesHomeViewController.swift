import UIKit

/// Native Versículos tab: book picker (names ↔ siglas), Temas / Listas / Leitura chips.
/// Large title restored; Siglas/Nomes lives on the Old Testament header row inside the scroll view.
final class VersesHomeViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource {
    private enum HomeFilter: String {
        case books = "books"
        case themes = "themes"
        case lists = "lists"
        case reading = "reading"
    }

    private let chips = V2NFilterChipsView()
    private let modeToggle = V2NModeToggle()
    private let emptyState = V2NEmptyStateView()
    private let contentHost = UIView()
    private let booksPanel = UIView()
    private var collectionView: UICollectionView!

    private var books: [NativeAPIClient.BibleBookDTO] = []
    private var filtered: [NativeAPIClient.BibleBookDTO] = []
    private var prefs: NativeAPIClient.PrefsDTO?
    private var booksCompact = false
    private var homeFilter: HomeFilter = .books
    /// Guards against overlapping reloads leaving the compositional layout stuck empty.
    private var booksLoadToken = 0
    /// When true, wait until the collection view has a real width before invalidating layout.
    private var pendingLayoutRefresh = false

    private lazy var themesVC = ThemesHomeViewController(prefs: nil, embedded: true)
    private lazy var listsVC = MyCollectionsViewController(embedded: true)
    private lazy var readingVC = ReadingHomeViewController(embedded: true)

    private var otBooks: [NativeAPIClient.BibleBookDTO] { filtered.filter { $0.testament == "ot" } }
    private var ntBooks: [NativeAPIClient.BibleBookDTO] { filtered.filter { $0.testament == "nt" } }

    override func viewDidLoad() {
        super.viewDidLoad()
        V2NChrome.styleCanvas(view)
        title = String(localized: "Versículos")
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always

        applyBooksCompact(resolvedInitialBooksCompact(), rebuild: false)
        modeToggle.onChange = { [weak self] compact in
            self?.applyBooksCompact(compact, rebuild: true)
            if NativeAPIClient.hasBearer {
                Task { try? await NativeAPIClient.patchPrefs(["booksCompact": compact]) }
            }
        }

        chips.configure(
            chips: [
                V2NFilterChip(id: HomeFilter.books.rawValue, title: String(localized: "Livros"), systemImage: "book"),
                V2NFilterChip(id: HomeFilter.themes.rawValue, title: String(localized: "Temas"), systemImage: "tag"),
                V2NFilterChip(id: HomeFilter.lists.rawValue, title: String(localized: "Listas"), systemImage: "bookmark"),
                V2NFilterChip(id: HomeFilter.reading.rawValue, title: String(localized: "Leitura"), systemImage: "calendar"),
            ],
            selectedId: HomeFilter.books.rawValue
        )
        chips.onSelect = { [weak self] id in
            self?.selectFilter(id)
        }

        contentHost.translatesAutoresizingMaskIntoConstraints = false
        contentHost.backgroundColor = .clear
        booksPanel.translatesAutoresizingMaskIntoConstraints = false
        booksPanel.backgroundColor = .clear

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

        view.addSubview(chips)
        view.addSubview(contentHost)
        contentHost.addSubview(booksPanel)
        // Siglas/Nomes lives in the OT section header (scroll content), not above the list.
        booksPanel.addSubview(collectionView)
        booksPanel.addSubview(emptyState)

        NSLayoutConstraint.activate([
            chips.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: V2NDesign.Space.xxs),
            chips.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chips.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            contentHost.topAnchor.constraint(equalTo: chips.bottomAnchor, constant: V2NDesign.Space.xs),
            contentHost.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentHost.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentHost.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            booksPanel.topAnchor.constraint(equalTo: contentHost.topAnchor),
            booksPanel.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
            booksPanel.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
            booksPanel.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor),

            collectionView.topAnchor.constraint(equalTo: booksPanel.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: booksPanel.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: booksPanel.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: booksPanel.bottomAnchor),

            emptyState.topAnchor.constraint(equalTo: booksPanel.topAnchor),
            emptyState.leadingAnchor.constraint(equalTo: booksPanel.leadingAnchor),
            emptyState.trailingAnchor.constraint(equalTo: booksPanel.trailingAnchor),
            emptyState.bottomAnchor.constraint(equalTo: booksPanel.bottomAnchor),
        ])

        embedChild(themesVC)
        embedChild(listsVC)
        embedChild(readingVC)
        themesVC.view.isHidden = true
        listsVC.view.isHidden = true
        readingVC.view.isHidden = true
        contentHost.bringSubviewToFront(booksPanel)

        _ = V2NGlassMaterial.sdkHasLiquidGlass()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always
        Task { @MainActor in
            if NativeAPIClient.hasBearer {
                _ = await NativeSessionBootstrap.migrateCookieToKeychainIfNeeded()
            }
            switch homeFilter {
            case .books: reload()
            case .themes: themesVC.reloadFromParent()
            case .lists: listsVC.reloadFromParent()
            case .reading: readingVC.reloadFromParent()
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if pendingLayoutRefresh, collectionView.bounds.width > 1 {
            refreshCollectionLayoutIfNeeded(force: true)
        }
    }

    /// Deep links / parent chrome: switch the Versículos chip without a user tap.
    func selectHomeFilter(_ id: String) {
        chips.setSelected(id)
        selectFilter(id)
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
    }

    private func resolvedInitialBooksCompact() -> Bool {
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

    /// Root cause of the empty-on-launch grid: `invalidateLayout()` while the
    /// collection view still had zero width / empty data left Compositional Layout
    /// stuck until Siglas/Nomes forced another invalidate. Only invalidate when we
    /// have a real width; otherwise defer to `viewDidLayoutSubviews`.
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

    private func selectFilter(_ id: String) {
        guard let filter = HomeFilter(rawValue: id) else { return }
        homeFilter = filter
        updateChromeForFilter()
        switch filter {
        case .books:
            booksPanel.isHidden = false
            themesVC.view.isHidden = true
            listsVC.view.isHidden = true
            readingVC.view.isHidden = true
            contentHost.bringSubviewToFront(booksPanel)
            applyFilter()
            refreshCollectionLayoutIfNeeded(force: true)
        case .themes:
            emptyState.hide()
            booksPanel.isHidden = true
            themesVC.updatePrefs(prefs)
            themesVC.view.isHidden = false
            listsVC.view.isHidden = true
            readingVC.view.isHidden = true
            contentHost.bringSubviewToFront(themesVC.view)
            themesVC.reloadFromParent()
        case .lists:
            emptyState.hide()
            booksPanel.isHidden = true
            themesVC.view.isHidden = true
            listsVC.view.isHidden = false
            readingVC.view.isHidden = true
            contentHost.bringSubviewToFront(listsVC.view)
            listsVC.reloadFromParent()
        case .reading:
            emptyState.hide()
            booksPanel.isHidden = true
            themesVC.view.isHidden = true
            listsVC.view.isHidden = true
            readingVC.view.isHidden = false
            contentHost.bringSubviewToFront(readingVC.view)
            readingVC.reloadFromParent()
        }
    }

    private func updateChromeForFilter() {
        switch homeFilter {
        case .books, .themes:
            navigationItem.rightBarButtonItems = nil
            navigationItem.searchController = nil
        case .lists:
            navigationItem.searchController = nil
            navigationItem.rightBarButtonItems = [
                UIBarButtonItem(title: String(localized: "Nova"), style: .plain, target: self, action: #selector(createListFromParent)),
            ]
        case .reading:
            navigationItem.rightBarButtonItems = nil
            // Reading keeps its search in the content area when embedded.
            navigationItem.searchController = nil
        }
    }

    @objc private func createListFromParent() {
        listsVC.presentCreateList()
    }

    @objc private func reload() {
        booksLoadToken += 1
        let token = booksLoadToken
        Task { @MainActor in
            defer { collectionView.refreshControl?.endRefreshing() }
            do {
                async let booksTask = NativeAPIClient.fetchBibleBooks(locale: AppLocale.apiCode)
                if NativeAPIClient.hasBearer {
                    prefs = try? await NativeAPIClient.getPrefs()
                    if let prefs {
                        // Sync Siglas/Nomes from prefs without an early layout invalidate
                        // (that was emptying the grid until the user tapped the toggle).
                        applyBooksCompact(prefs.booksCompact, rebuild: false)
                        themesVC.updatePrefs(prefs)
                    }
                }
                let loaded = try await booksTask
                guard token == booksLoadToken else { return }
                books = loaded
                applyFilter()
                refreshCollectionLayoutIfNeeded(force: true)
            } catch {
                guard token == booksLoadToken else { return }
                applyFilter()
            }
        }
    }

    private func applyFilter() {
        guard homeFilter == .books else { return }
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
