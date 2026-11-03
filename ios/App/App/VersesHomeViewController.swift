import UIKit

/// Native Versículos tab: book picker (names ↔ siglas), Temas / Listas chips.
/// Chips keep title + filter chrome fixed and swap only the content below.
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
    private let contentHost = UIView()
    private let booksPanel = UIView()
    private var collectionView: UICollectionView!
    private let search = UISearchController(searchResultsController: nil)

    private var books: [NativeAPIClient.BibleBookDTO] = []
    private var filtered: [NativeAPIClient.BibleBookDTO] = []
    private var prefs: NativeAPIClient.PrefsDTO?
    private var booksCompact = false
    private var homeFilter: HomeFilter = .books
    private var searchVisible = false

    private lazy var themesVC = ThemesHomeViewController(prefs: nil, embedded: true)
    private lazy var listsVC = MyCollectionsViewController(embedded: true)

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

        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = String(localized: "Buscar livro")
        definesPresentationContext = true
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

        contentHost.translatesAutoresizingMaskIntoConstraints = false
        contentHost.backgroundColor = .clear
        booksPanel.translatesAutoresizingMaskIntoConstraints = false
        booksPanel.backgroundColor = .clear

        let layout = makeLayout()
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.alwaysBounceVertical = true
        collectionView.register(BookNameCell.self, forCellWithReuseIdentifier: BookNameCell.reuseId)
        collectionView.register(BookAbbrCell.self, forCellWithReuseIdentifier: BookAbbrCell.reuseId)
        collectionView.register(
            SectionHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: SectionHeaderView.reuseId
        )
        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(reload), for: .valueChanged)
        collectionView.refreshControl = refresh

        view.addSubview(chips)
        view.addSubview(contentHost)
        contentHost.addSubview(booksPanel)
        booksPanel.addSubview(modeToggle)
        booksPanel.addSubview(statusBanner)
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

            modeToggle.topAnchor.constraint(equalTo: booksPanel.topAnchor),
            modeToggle.trailingAnchor.constraint(equalTo: booksPanel.layoutMarginsGuide.trailingAnchor),
            modeToggle.leadingAnchor.constraint(greaterThanOrEqualTo: booksPanel.layoutMarginsGuide.leadingAnchor),

            statusBanner.topAnchor.constraint(equalTo: modeToggle.bottomAnchor, constant: V2NDesign.Space.xxs),
            statusBanner.leadingAnchor.constraint(equalTo: booksPanel.layoutMarginsGuide.leadingAnchor),
            statusBanner.trailingAnchor.constraint(equalTo: booksPanel.layoutMarginsGuide.trailingAnchor),

            collectionView.topAnchor.constraint(equalTo: statusBanner.bottomAnchor, constant: V2NDesign.Space.xs),
            collectionView.leadingAnchor.constraint(equalTo: booksPanel.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: booksPanel.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: booksPanel.bottomAnchor),

            emptyState.topAnchor.constraint(equalTo: statusBanner.bottomAnchor),
            emptyState.leadingAnchor.constraint(equalTo: booksPanel.leadingAnchor),
            emptyState.trailingAnchor.constraint(equalTo: booksPanel.trailingAnchor),
            emptyState.bottomAnchor.constraint(equalTo: booksPanel.bottomAnchor),
        ])

        embedChild(themesVC)
        embedChild(listsVC)
        themesVC.view.isHidden = true
        listsVC.view.isHidden = true

        _ = V2NGlassMaterial.sdkHasLiquidGlass()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task { @MainActor in
            if NativeAPIClient.hasBearer {
                _ = await NativeSessionBootstrap.migrateCookieToKeychainIfNeeded()
            }
            switch homeFilter {
            case .books: reload()
            case .themes: themesVC.reloadFromParent()
            case .lists: listsVC.reloadFromParent()
            }
        }
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
            rebuildLayout()
        }
    }

    @objc private func toggleSearch() {
        guard homeFilter == .books else { return }
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
            booksPanel.isHidden = false
            themesVC.view.isHidden = true
            listsVC.view.isHidden = true
            applyFilter()
        case .themes:
            dismissBooksSearchIfNeeded()
            booksPanel.isHidden = true
            themesVC.updatePrefs(prefs)
            themesVC.view.isHidden = false
            listsVC.view.isHidden = true
            themesVC.reloadFromParent()
        case .lists:
            dismissBooksSearchIfNeeded()
            booksPanel.isHidden = true
            themesVC.view.isHidden = true
            listsVC.view.isHidden = false
            listsVC.reloadFromParent()
        }
    }

    private func dismissBooksSearchIfNeeded() {
        emptyState.hide()
        guard searchVisible else { return }
        searchVisible = false
        search.isActive = false
        search.searchBar.text = nil
        navigationItem.searchController = nil
    }

    private func updateChromeForFilter() {
        switch homeFilter {
        case .books:
            navigationItem.rightBarButtonItems = [
                UIBarButtonItem(image: UIImage(systemName: "magnifyingglass"), style: .plain, target: self, action: #selector(toggleSearch)),
            ]
            navigationItem.rightBarButtonItem?.accessibilityLabel = String(localized: "Buscar")
        case .lists:
            navigationItem.rightBarButtonItems = [
                UIBarButtonItem(title: String(localized: "Nova"), style: .plain, target: self, action: #selector(createListFromParent)),
            ]
        case .themes:
            navigationItem.rightBarButtonItems = nil
        }
    }

    @objc private func createListFromParent() {
        listsVC.presentCreateList()
    }

    @objc private func reload() {
        Task { @MainActor in
            defer { collectionView.refreshControl?.endRefreshing() }
            do {
                async let booksTask = NativeAPIClient.fetchBibleBooks(locale: AppLocale.apiCode)
                if NativeAPIClient.hasBearer {
                    prefs = try? await NativeAPIClient.getPrefs()
                    if let prefs {
                        applyBooksCompact(prefs.booksCompact, rebuild: true)
                        themesVC.updatePrefs(prefs)
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
        guard homeFilter == .books else { return }
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
            collectionView.isHidden = false
        }
        collectionView.reloadData()
    }

    func updateSearchResults(for searchController: UISearchController) {
        applyFilter()
    }

    private func rebuildLayout() {
        collectionView.collectionViewLayout.invalidateLayout()
        collectionView.reloadData()
    }

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { [weak self] _, env in
            let compact = self?.booksCompact ?? false
            let columns: CGFloat = compact ? (env.container.effectiveContentSize.width > 500 ? 8 : 5) : 2
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1 / columns),
                heightDimension: .absolute(compact ? 52 : 56)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            item.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .absolute(compact ? 52 : 56)
            )
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 12, bottom: 12, trailing: 12)
            let header = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(32)),
                elementKind: UICollectionView.elementKindSectionHeader,
                alignment: .top
            )
            section.boundarySupplementaryItems = [header]
            return section
        }
    }

    // MARK: - Collection

    func numberOfSections(in collectionView: UICollectionView) -> Int { 2 }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        section == 0 ? otBooks.count : ntBooks.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let book = (indexPath.section == 0 ? otBooks : ntBooks)[indexPath.item]
        if booksCompact {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: BookAbbrCell.reuseId, for: indexPath) as! BookAbbrCell
            cell.configure(abbr: book.abbr, accessibilityName: book.name)
            return cell
        }
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: BookNameCell.reuseId, for: indexPath) as! BookNameCell
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
            withReuseIdentifier: SectionHeaderView.reuseId,
            for: indexPath
        ) as! SectionHeaderView
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

// MARK: - Cells

private final class BookNameCell: UICollectionViewCell {
    static let reuseId = "BookNameCell"
    private let nameLabel = UILabel()
    private let abbrLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = V2NDesign.surface
        contentView.layer.cornerRadius = V2NDesign.Radius.sm
        contentView.layer.cornerCurve = .continuous
        contentView.layer.borderWidth = 0.5
        contentView.layer.borderColor = V2NDesign.separator.cgColor

        nameLabel.font = V2NDesign.preferred(.subheadline, weight: .medium)
        nameLabel.textColor = .label
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        abbrLabel.font = V2NDesign.caption()
        abbrLabel.textColor = .secondaryLabel
        abbrLabel.setContentHuggingPriority(.required, for: .horizontal)
        abbrLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(nameLabel)
        contentView.addSubview(abbrLabel)
        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            nameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            abbrLabel.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 6),
            abbrLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            abbrLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(name: String, abbr: String) {
        nameLabel.text = name
        abbrLabel.text = abbr
        accessibilityLabel = "\(name), \(abbr)"
        isAccessibilityElement = true
    }
}

private final class BookAbbrCell: UICollectionViewCell {
    static let reuseId = "BookAbbrCell"
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = V2NDesign.surface
        contentView.layer.cornerRadius = V2NDesign.Radius.sm
        contentView.layer.cornerCurve = .continuous
        contentView.layer.borderWidth = 0.5
        contentView.layer.borderColor = V2NDesign.separator.cgColor

        label.font = V2NDesign.preferred(.footnote, weight: .semibold)
        label.textColor = .label
        label.textAlignment = .center
        label.adjustsFontForContentSizeCategory = true
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -2),
        ])
        isAccessibilityElement = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(abbr: String, accessibilityName: String) {
        label.text = abbr
        accessibilityLabel = accessibilityName
    }
}

private final class SectionHeaderView: UICollectionReusableView {
    static let reuseId = "SectionHeaderView"
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = V2NDesign.sectionHeader()
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String) {
        label.text = title.uppercased()
    }
}
