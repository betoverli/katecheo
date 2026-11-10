import UIKit

// MARK: - Chapter picker (number grid)

final class VerseChapterViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource {
    private let book: NativeAPIClient.BibleBookDTO
    private let prefs: NativeAPIClient.PrefsDTO?
    private var collectionView: UICollectionView!
    private let hintLabel = UILabel()

    init(book: NativeAPIClient.BibleBookDTO, prefs: NativeAPIClient.PrefsDTO?) {
        self.book = book
        self.prefs = prefs
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        V2NChrome.styleScreen(view)
        title = book.name

        hintLabel.text = String(localized: "Capítulo")
        hintLabel.font = V2NDesign.sectionHeader()
        hintLabel.textColor = .secondaryLabel
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: V2NNumberGridLayout.make())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(V2NNumberCell.self, forCellWithReuseIdentifier: V2NNumberCell.reuseId)

        view.addSubview(hintLabel)
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            hintLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: V2NDesign.Space.sm),
            hintLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            hintLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),

            collectionView.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: V2NDesign.Space.xs),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        _ = V2NGlassMaterial.sdkHasLiquidGlass()
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        book.chapters
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: V2NNumberCell.reuseId, for: indexPath) as? V2NNumberCell else {
            return UICollectionViewCell()
        }
        cell.configure(number: indexPath.item + 1, style: .plain)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        V2NHaptics.selection()
        let chapter = indexPath.item + 1
        let verseCount = book.verses.indices.contains(indexPath.item) ? book.verses[indexPath.item] : 0
        navigationController?.pushViewController(
            VerseNumberViewController(book: book, chapter: chapter, verseCount: verseCount, prefs: prefs),
            animated: true
        )
    }
}

// MARK: - Verse number picker (grid + range: first tap start, second tap end)

final class VerseNumberViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource {
    private let book: NativeAPIClient.BibleBookDTO
    private let chapter: Int
    private let verseCount: Int
    private let prefs: NativeAPIClient.PrefsDTO?
    private var rangeStart: Int?
    private var rangeEnd: Int?
    private var collectionView: UICollectionView!
    private let hintLabel = UILabel()

    init(book: NativeAPIClient.BibleBookDTO, chapter: Int, verseCount: Int, prefs: NativeAPIClient.PrefsDTO?) {
        self.book = book
        self.chapter = chapter
        self.verseCount = verseCount
        self.prefs = prefs
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        V2NChrome.styleScreen(view)
        title = String(localized: "\(book.abbr) \(chapter)")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: String(localized: "Capítulo inteiro"),
            style: .plain,
            target: self,
            action: #selector(selectWholeChapter)
        )

        hintLabel.font = V2NDesign.caption()
        hintLabel.textColor = .secondaryLabel
        hintLabel.numberOfLines = 0
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        refreshHint()

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: V2NNumberGridLayout.make())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(V2NNumberCell.self, forCellWithReuseIdentifier: V2NNumberCell.reuseId)

        view.addSubview(hintLabel)
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            hintLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: V2NDesign.Space.sm),
            hintLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            hintLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),

            collectionView.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: V2NDesign.Space.xs),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        _ = V2NGlassMaterial.sdkHasLiquidGlass()
    }

    private func refreshHint() {
        if let rangeStart, rangeEnd == nil {
            hintLabel.text = String(localized: "Toque no versículo final (início: \(rangeStart))")
        } else {
            hintLabel.text = String(localized: "Toque para escolher · segundo toque define o intervalo")
        }
    }

    @objc private func selectWholeChapter() {
        openActions(passage: NativeAPIClient.PassageDTO(
            bookId: book.id,
            chapter: chapter,
            verseStart: nil,
            verseEnd: nil
        ))
    }

    private func style(for verse: Int) -> V2NNumberCell.Style {
        if let start = rangeStart, let end = rangeEnd {
            let lo = min(start, end)
            let hi = max(start, end)
            if verse == lo || verse == hi { return .edge }
            if verse > lo && verse < hi { return .inRange }
            return .plain
        }
        if let start = rangeStart, verse == start { return .edge }
        return .plain
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        verseCount
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: V2NNumberCell.reuseId, for: indexPath) as? V2NNumberCell else {
            return UICollectionViewCell()
        }
        let verse = indexPath.item + 1
        cell.configure(number: verse, style: style(for: verse))
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        V2NHaptics.selection()
        let verse = indexPath.item + 1
        if rangeStart == nil || rangeEnd != nil {
            rangeStart = verse
            rangeEnd = nil
            refreshHint()
            collectionView.reloadData()
            return
        }
        rangeEnd = verse
        refreshHint()
        collectionView.reloadData()
        let start = min(rangeStart!, rangeEnd!)
        let end = max(rangeStart!, rangeEnd!)
        // Brief highlight of the contiguous range, then open actions.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self else { return }
            self.openActions(passage: NativeAPIClient.PassageDTO(
                bookId: self.book.id,
                chapter: self.chapter,
                verseStart: start,
                verseEnd: end == start ? start : end
            ))
        }
    }

    private func openActions(passage: NativeAPIClient.PassageDTO) {
        let label = formatLabel(passage)
        let actions = VerseActionsViewController(passage: passage, label: label, prefs: prefs)
        navigationController?.pushViewController(actions, animated: true)
    }

    private func formatLabel(_ passage: NativeAPIClient.PassageDTO) -> String {
        BibleBookCatalog.formatPassage(
            bookId: passage.bookId,
            chapter: passage.chapter,
            verseStart: passage.verseStart,
            verseEnd: passage.verseEnd
        )
    }
}

// MARK: - Actions for a selected passage

final class VerseActionsViewController: UITableViewController {
    private enum Row: Int, CaseIterable {
        case openBible
        case share
        case copy
        case addToNote
        case saveToList
    }

    private let passage: NativeAPIClient.PassageDTO
    private let label: String
    private var prefs: NativeAPIClient.PrefsDTO?
    private var linkItem: NativeAPIClient.LinkItemDTO?
    private let statusLabel = UILabel()

    init(passage: NativeAPIClient.PassageDTO, label: String, prefs: NativeAPIClient.PrefsDTO?) {
        self.passage = passage
        self.label = label
        self.prefs = prefs
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        v2nApplyGroupedChrome()
        title = label
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "action")
        statusLabel.numberOfLines = 0
        statusLabel.font = V2NDesign.caption()
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        let header = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 72))
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -20),
            statusLabel.topAnchor.constraint(equalTo: header.topAnchor, constant: 12),
            statusLabel.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -8),
        ])
        tableView.tableHeaderView = header
        _ = V2NGlassMaterial.sdkHasLiquidGlass()
        Task { await resolveLink() }
    }

    private func resolveLink() async {
        do {
            if prefs == nil, NativeAPIClient.hasBearer {
                prefs = try? await NativeAPIClient.getPrefs()
            }
            linkItem = try await NativeAPIClient.resolveBibleLink(
                passage: passage,
                appId: prefs?.appId,
                translationId: prefs?.translationId,
                preferNative: prefs?.preferNative
            )
            await MainActor.run {
                statusLabel.text = linkItem?.url ?? String(localized: "Link pronto")
                tableView.reloadData()
            }
        } catch {
            await MainActor.run {
                statusLabel.text = String(localized: "Link indisponível: \(error.localizedDescription)")
            }
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        Row.allCases.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "action", for: indexPath)
        var config = cell.defaultContentConfiguration()
        guard let row = Row(rawValue: indexPath.row) else { return cell }
        let symbol: String
        switch row {
        case .openBible:
            config.text = String(localized: "Abrir na Bíblia")
            config.secondaryText = ProfileBibleCatalog.name(for: prefs?.appId ?? "youversion")
            symbol = "book.fill"
        case .share:
            config.text = String(localized: "Compartilhar")
            symbol = "square.and.arrow.up"
        case .copy:
            config.text = String(localized: "Copiar referência")
            symbol = "doc.on.doc"
        case .addToNote:
            config.text = String(localized: "Adicionar à nota de hoje")
            symbol = "note.text.badge.plus"
        case .saveToList:
            config.text = String(localized: "Salvar na minha lista")
            symbol = "bookmark"
        }
        config.v2nApplyBrandListStyle(symbol: symbol)
        cell.contentConfiguration = config
        cell.v2nApplyBrandChrome()
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let row = Row(rawValue: indexPath.row) else { return }
        switch row {
        case .openBible: openBible()
        case .share: share()
        case .copy: copyRef()
        case .addToNote: addToNote()
        case .saveToList: saveToList()
        }
    }

    private func openBible() {
        Task { @MainActor in
            if linkItem == nil { await resolveLink() }
            guard let raw = linkItem?.url, let url = URL(string: raw) else {
                presentAlert(title: String(localized: "Sem link"), message: String(localized: "Não foi possível montar o link da Bíblia."))
                return
            }
            await UIApplication.shared.open(url)
        }
    }

    private func share() {
        Task { @MainActor in
            if linkItem == nil { await resolveLink() }
            let text = linkItem?.plain ?? label
            let url = linkItem.flatMap { URL(string: $0.url) }
            var items: [Any] = [text]
            if let url { items.append(url) }
            let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
            if let pop = vc.popoverPresentationController {
                pop.sourceView = tableView
            }
            present(vc, animated: true)
        }
    }

    private func copyRef() {
        UIPasteboard.general.string = linkItem?.plain ?? label
        statusLabel.text = String(localized: "Copiado: \(label)")
    }

    private func addToNote() {
        guard NativeAPIClient.hasBearer else {
            presentSignInNeeded()
            return
        }
        Task { @MainActor in
            do {
                let result = try await NativeAPIClient.appendVerse(passage)
                statusLabel.text = String(localized: "Adicionado à nota: \(result.label)")
                let alert = UIAlertController(
                    title: String(localized: "Na nota de hoje"),
                    message: String(localized: "\(result.label) foi inserido como referência (bibleRef)."),
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
                alert.addAction(UIAlertAction(title: String(localized: "Abrir nota"), style: .default) { [weak self] _ in
                    self?.openNote(result.note)
                })
                present(alert, animated: true)
            } catch NativeAPIClient.APIError.unauthorized {
                presentSignInNeeded()
            } catch {
                presentAlert(title: String(localized: "Não foi possível adicionar"), message: error.localizedDescription)
            }
        }
    }

    private func openNote(_ note: NativeAPIClient.NoteDocument) {
        guard let tabs = tabBarController else { return }
        // Caderno is index 0 in NativeRootTabBarController.
        tabs.selectedIndex = 0
        if let nav = tabs.viewControllers?[0] as? UINavigationController {
            let detail = NoteDetailViewController(noteId: note.id, initial: note)
            nav.popToRootViewController(animated: false)
            nav.pushViewController(detail, animated: true)
        }
    }

    private func saveToList() {
        guard NativeAPIClient.hasBearer else {
            presentSignInNeeded()
            return
        }
        Task { @MainActor in
            do {
                let collections = try await NativeAPIClient.listMyCollections()
                if collections.isEmpty {
                    let created = try await NativeAPIClient.savePassageToCollection(
                        passage: passage,
                        title: String(localized: "Minha lista")
                    )
                    statusLabel.text = String(localized: "Salvo em «\(created.title)»")
                    return
                }
                let sheet = UIAlertController(title: String(localized: "Salvar na lista"), message: nil, preferredStyle: .actionSheet)
                sheet.view.tintColor = V2NDesign.accent
                for collection in collections {
                    sheet.addAction(UIAlertAction(title: collection.title, style: .default) { [weak self] _ in
                        self?.save(to: collection.id)
                    })
                }
                sheet.addAction(UIAlertAction(title: String(localized: "Nova lista…"), style: .default) { [weak self] _ in
                    self?.promptNewList()
                })
                sheet.addAction(UIAlertAction(title: String(localized: "Cancelar"), style: .cancel))
                if let pop = sheet.popoverPresentationController {
                    pop.sourceView = tableView
                }
                present(sheet, animated: true)
            } catch {
                presentAlert(title: String(localized: "Listas"), message: error.localizedDescription)
            }
        }
    }

    private func save(to collectionId: String) {
        Task { @MainActor in
            do {
                let collection = try await NativeAPIClient.savePassageToCollection(
                    passage: passage,
                    collectionId: collectionId
                )
                statusLabel.text = String(localized: "Salvo em «\(collection.title)»")
            } catch {
                presentAlert(title: String(localized: "Não foi possível salvar"), message: error.localizedDescription)
            }
        }
    }

    private func promptNewList() {
        let form = V2NNamedCreateViewController(kind: .list) { [weak self] name in
            guard let self else { return }
            Task { @MainActor in
                do {
                    let collection = try await NativeAPIClient.savePassageToCollection(
                        passage: self.passage,
                        title: name
                    )
                    if let nav = self.presentedViewController as? UINavigationController,
                       let form = nav.viewControllers.first as? V2NNamedCreateViewController
                    {
                        form.finishSuccess()
                    } else {
                        self.dismiss(animated: true)
                    }
                    self.statusLabel.text = String(localized: "Salvo em «\(collection.title)»")
                } catch {
                    if let nav = self.presentedViewController as? UINavigationController,
                       let form = nav.viewControllers.first as? V2NNamedCreateViewController
                    {
                        form.presentFailure(error.localizedDescription)
                    } else {
                        self.presentAlert(title: String(localized: "Não foi possível salvar"), message: error.localizedDescription)
                    }
                }
            }
        }
        let nav = UINavigationController(rootViewController: form)
        V2NChrome.style(navigationController: nav)
        if #available(iOS 15.0, *) {
            if let sheet = nav.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
            }
        }
        present(nav, animated: true)
    }

    private func presentSignInNeeded() {
        presentAlert(title: String(localized: "Entrar"), message: String(localized: "Inicie sessão na aba Perfil ou Caderno para salvar versículos."))
    }

    private func presentAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.view.tintColor = V2NDesign.accent
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Themes (built-in collections)

final class ThemesHomeViewController: UITableViewController, UISearchResultsUpdating, UISearchBarDelegate {
    private var prefs: NativeAPIClient.PrefsDTO?
    private let embedded: Bool
    private var categories: [NativeAPIClient.CategoryCardDTO] = []
    private var themes: [NativeAPIClient.ThemeCardDTO] = []
    private var kind = "index"
    private let search = UISearchController(searchResultsController: nil)
    private let emptyState = V2NEmptyStateView()

    init(prefs: NativeAPIClient.PrefsDTO?, embedded: Bool = false) {
        self.prefs = prefs
        self.embedded = embedded
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        v2nApplyGroupedChrome()
        if !embedded {
            title = String(localized: "Temas")
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: String(localized: "Novo"),
                style: .plain,
                target: self,
                action: #selector(createTheme)
            )
            navigationItem.rightBarButtonItem?.accessibilityLabel = String(localized: "Novo tema")
            navigationItem.rightBarButtonItem?.tintColor = V2NDesign.accent
        }
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "theme")
        tableView.backgroundView = emptyState
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = String(localized: "Buscar temas")
        search.searchBar.tintColor = V2NDesign.accent
        if embedded {
            // Parent Ferramentas owns navigationItem.searchController (pull-to-reveal).
            // No permanent embedded search bar.
        } else {
            navigationItem.searchController = search
            navigationItem.hidesSearchBarWhenScrolling = true
        }
        refreshControl = UIRefreshControl()
        refreshControl?.tintColor = V2NDesign.accent
        refreshControl?.addTarget(self, action: #selector(pullToRefresh), for: .valueChanged)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(catalogDidChange),
            name: NativeCatalogSync.themesDidChange,
            object: nil
        )
        _ = V2NGlassMaterial.sdkHasLiquidGlass()
        if !embedded {
            reload(forceNetwork: false)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func pullToRefresh() {
        reload(forceNetwork: true)
    }

    @objc private func catalogDidChange() {
        reload(forceNetwork: true)
    }

    @objc private func createTheme() {
        guard NativeAPIClient.hasBearer else {
            let alert = UIAlertController(
                title: String(localized: "Entrar"),
                message: String(localized: "Inicie sessão para criar um tema pessoal."),
                preferredStyle: .alert
            )
            alert.view.tintColor = V2NDesign.accent
            alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
            present(alert, animated: true)
            return
        }
        let form = V2NNamedCreateViewController(kind: .theme) { [weak self] name in
            guard let self else { return }
            Task { @MainActor in
                do {
                    // Personal themes are stored as user collections (same backend as Listas).
                    let created = try await NativeAPIClient.createMyCollection(title: name)
                    if let nav = self.presentedViewController as? UINavigationController,
                       let form = nav.viewControllers.first as? V2NNamedCreateViewController
                    {
                        form.finishSuccess()
                    } else {
                        self.dismiss(animated: true)
                    }
                    self.navigationController?.pushViewController(
                        MyCollectionDetailViewController(collection: created),
                        animated: true
                    )
                } catch {
                    if let nav = self.presentedViewController as? UINavigationController,
                       let form = nav.viewControllers.first as? V2NNamedCreateViewController
                    {
                        form.presentFailure(error.localizedDescription)
                    }
                }
            }
        }
        let nav = UINavigationController(rootViewController: form)
        V2NChrome.style(navigationController: nav)
        if #available(iOS 15.0, *) {
            if let sheet = nav.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
            }
        }
        present(nav, animated: true)
    }

    func updatePrefs(_ prefs: NativeAPIClient.PrefsDTO?) {
        self.prefs = prefs
    }

    func reloadFromParent() {
        // Cache-first — no appear poll. Push / version / pull-to-refresh force network.
        reload(forceNetwork: false)
    }

    /// Parent Tools search forwards here when Temas is selected.
    func applyParentSearchQuery(_ query: String) {
        search.searchBar.text = query
        reload(forceNetwork: true)
    }

    var parentSearchController: UISearchController { search }

    @objc private func reload() {
        reload(forceNetwork: refreshControl?.isRefreshing == true)
    }

    private func reload(forceNetwork: Bool) {
        Task { @MainActor in
            defer { refreshControl?.endRefreshing() }
            let q = (search.searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            do {
                let result = try await NativeAPIClient.fetchThemes(
                    query: q.isEmpty ? nil : q,
                    force: forceNetwork || !q.isEmpty
                )
                kind = result.kind
                categories = result.categories
                themes = result.themes
                tableView.reloadData()
                refreshEmptyState()
            } catch {
                if categories.isEmpty && themes.isEmpty {
                    let alert = UIAlertController(title: String(localized: "Temas"), message: error.localizedDescription, preferredStyle: .alert)
                    alert.view.tintColor = V2NDesign.accent
                    alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
                    present(alert, animated: true)
                }
            }
        }
    }

    private func refreshEmptyState() {
        if categories.isEmpty && themes.isEmpty {
            emptyState.show(
                symbol: "bookmark.fill",
                title: String(localized: "Nenhum tema encontrado."),
                message: String(localized: "Tente outra busca ou crie um tema pessoal.")
            )
        } else {
            emptyState.hide()
        }
    }

    func updateSearchResults(for searchController: UISearchController) {
        reload(forceNetwork: true)
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        reload(forceNetwork: true)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        reload(forceNetwork: true)
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        if categories.isEmpty && themes.isEmpty { return 0 }
        return themes.isEmpty ? 1 : 2
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 0 { return categories.isEmpty ? nil : String(localized: "Categorias") }
        return String(localized: "Temas")
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 { return categories.count }
        return themes.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "theme", for: indexPath)
        var config = cell.defaultContentConfiguration()
        if indexPath.section == 0 {
            let category = categories[indexPath.row]
            config.text = category.name
            if let count = category.count {
                config.secondaryText = String(localized: "\(count) temas")
            }
            config.v2nApplyBrandListStyle(symbol: "folder.fill")
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
        } else {
            let theme = themes[indexPath.row]
            config.text = theme.name
            config.secondaryText = theme.snippet
            config.v2nApplyBrandListStyle(symbol: "bookmark.fill")
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
        }
        cell.contentConfiguration = config
        cell.v2nApplyBrandChrome()
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            guard !categories.isEmpty else { return }
            let category = categories[indexPath.row]
            navigationController?.pushViewController(
                ThemeCategoryViewController(category: category, prefs: prefs),
                animated: true
            )
        } else {
            let theme = themes[indexPath.row]
            navigationController?.pushViewController(
                ThemeDetailViewController(themeId: theme.id, themeName: theme.name, prefs: prefs),
                animated: true
            )
        }
    }
}

final class ThemeCategoryViewController: UITableViewController {
    private let category: NativeAPIClient.CategoryCardDTO
    private let prefs: NativeAPIClient.PrefsDTO?
    private var themes: [NativeAPIClient.ThemeCardDTO] = []

    init(category: NativeAPIClient.CategoryCardDTO, prefs: NativeAPIClient.PrefsDTO?) {
        self.category = category
        self.prefs = prefs
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        v2nApplyGroupedChrome()
        title = category.name
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "theme")
        Task { await load() }
    }

    private func load() async {
        do {
            let result = try await NativeAPIClient.fetchThemes(categoryId: category.id)
            await MainActor.run {
                themes = result.themes
                tableView.reloadData()
            }
        } catch {
            await MainActor.run {
                let alert = UIAlertController(title: String(localized: "Categoria"), message: error.localizedDescription, preferredStyle: .alert)
                alert.view.tintColor = V2NDesign.accent
                alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
                present(alert, animated: true)
            }
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        themes.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "theme", for: indexPath)
        let theme = themes[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = theme.name
        config.secondaryText = theme.snippet
        config.v2nApplyBrandListStyle(symbol: "bookmark.fill")
        cell.contentConfiguration = config
        cell.v2nApplyBrandChrome()
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let theme = themes[indexPath.row]
        navigationController?.pushViewController(
            ThemeDetailViewController(themeId: theme.id, themeName: theme.name, prefs: prefs),
            animated: true
        )
    }
}

final class ThemeDetailViewController: UITableViewController {
    private let themeId: String
    private let themeName: String
    private let prefs: NativeAPIClient.PrefsDTO?
    private var passages: [NativeAPIClient.ThemePassageDTO] = []

    init(themeId: String, themeName: String, prefs: NativeAPIClient.PrefsDTO?) {
        self.themeId = themeId
        self.themeName = themeName
        self.prefs = prefs
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        v2nApplyGroupedChrome()
        title = themeName
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "passage")
        Task { await load() }
    }

    private func load() async {
        do {
            let result = try await NativeAPIClient.fetchThemes(themeId: themeId)
            await MainActor.run {
                passages = result.passages
                tableView.reloadData()
            }
        } catch {
            await MainActor.run {
                let alert = UIAlertController(title: String(localized: "Tema"), message: error.localizedDescription, preferredStyle: .alert)
                alert.view.tintColor = V2NDesign.accent
                alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
                present(alert, animated: true)
            }
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        passages.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "passage", for: indexPath)
        let passage = passages[indexPath.row]
        var config = cell.defaultContentConfiguration()
        let localized = BibleBookCatalog.formatPassage(
            bookId: passage.bookId,
            chapter: passage.chapter,
            verseStart: passage.verseStart,
            verseEnd: passage.verseEnd
        )
        config.text = passage.label ?? localized
        config.secondaryText = passage.snippet
        config.v2nApplyBrandListStyle(symbol: "text.book.closed.fill")
        cell.contentConfiguration = config
        cell.v2nApplyBrandChrome()
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let passage = passages[indexPath.row]
        let localized = BibleBookCatalog.formatPassage(
            bookId: passage.bookId,
            chapter: passage.chapter,
            verseStart: passage.verseStart,
            verseEnd: passage.verseEnd
        )
        let actions = VerseActionsViewController(
            passage: passage.asPassage,
            label: passage.label ?? localized,
            prefs: prefs
        )
        navigationController?.pushViewController(actions, animated: true)
    }
}

// MARK: - User collections ("Minhas listas")

final class MyCollectionsViewController: UITableViewController {
    private let embedded: Bool
    private var collections: [NativeAPIClient.UserCollectionDTO] = []
    private var didPromptSignIn = false
    private let emptyState = V2NEmptyStateView()

    init(embedded: Bool = false) {
        self.embedded = embedded
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        v2nApplyGroupedChrome()
        if !embedded {
            title = String(localized: "Minhas listas")
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: String(localized: "Nova"),
                style: .plain,
                target: self,
                action: #selector(createList)
            )
            navigationItem.rightBarButtonItem?.accessibilityLabel = String(localized: "Nova lista")
            navigationItem.rightBarButtonItem?.tintColor = V2NDesign.accent
        }
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "list")
        // backgroundView + Auto Layout fights UITableView frame ownership (build-238:
        // empty copy + Nova lista sat indented). Use autoresizing fill instead.
        emptyState.translatesAutoresizingMaskIntoConstraints = true
        emptyState.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.backgroundView = emptyState
        refreshControl = UIRefreshControl()
        refreshControl?.tintColor = V2NDesign.accent
        refreshControl?.addTarget(self, action: #selector(reload), for: .valueChanged)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        v2nApplyTabBarScrollClearanceIfNeeded()
        if let bg = tableView.backgroundView {
            bg.frame = tableView.bounds
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !embedded {
            reload()
        }
    }

    func reloadFromParent() {
        reload()
    }

    func presentCreateList() {
        createList()
    }

    @objc private func reload() {
        Task { @MainActor in
            defer { refreshControl?.endRefreshing() }
            guard NativeAPIClient.hasBearer else {
                collections = []
                tableView.reloadData()
                refreshEmptyState(signedOut: true)
                // Embedded under Versículos chips: show empty row, don't steal focus with alerts every switch.
                if !embedded || !didPromptSignIn {
                    didPromptSignIn = true
                    let alert = UIAlertController(
                        title: String(localized: "Entrar"),
                        message: String(localized: "Inicie sessão para ver suas listas de versículos."),
                        preferredStyle: .alert
                    )
                    alert.view.tintColor = V2NDesign.accent
                    alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
                    present(alert, animated: true)
                }
                return
            }
            do {
                collections = try await NativeAPIClient.listMyCollections()
                tableView.reloadData()
                refreshEmptyState(signedOut: false)
            } catch {
                let alert = UIAlertController(title: String(localized: "Listas"), message: error.localizedDescription, preferredStyle: .alert)
                alert.view.tintColor = V2NDesign.accent
                alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
                present(alert, animated: true)
            }
        }
    }

    private func refreshEmptyState(signedOut: Bool) {
        if collections.isEmpty {
            if signedOut {
                emptyState.show(
                    symbol: "person.crop.circle.badge.questionmark",
                    title: String(localized: "Entrar"),
                    message: String(localized: "Inicie sessão para ver suas listas de versículos.")
                )
            } else {
                emptyState.show(
                    symbol: "list.bullet.rectangle",
                    title: String(localized: "Nenhuma lista ainda."),
                    message: String(localized: "Salve um versículo em «Salvar na minha lista»."),
                    actionTitle: String(localized: "Nova lista"),
                    action: { [weak self] in self?.createList() }
                )
            }
        } else {
            emptyState.hide()
        }
    }

    @objc private func createList() {
        guard NativeAPIClient.hasBearer else {
            let alert = UIAlertController(
                title: String(localized: "Entrar"),
                message: String(localized: "Inicie sessão para ver suas listas de versículos."),
                preferredStyle: .alert
            )
            alert.view.tintColor = V2NDesign.accent
            alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
            present(alert, animated: true)
            return
        }
        let form = V2NNamedCreateViewController(kind: .list) { [weak self] name in
            guard let self else { return }
            Task { @MainActor in
                do {
                    let created = try await NativeAPIClient.createMyCollection(title: name)
                    if let nav = self.presentedViewController as? UINavigationController,
                       let form = nav.viewControllers.first as? V2NNamedCreateViewController
                    {
                        form.finishSuccess()
                    } else {
                        self.dismiss(animated: true)
                    }
                    self.reload()
                    self.navigationController?.pushViewController(
                        MyCollectionDetailViewController(collection: created),
                        animated: true
                    )
                } catch {
                    if let nav = self.presentedViewController as? UINavigationController,
                       let form = nav.viewControllers.first as? V2NNamedCreateViewController
                    {
                        form.presentFailure(error.localizedDescription)
                    }
                }
            }
        }
        let nav = UINavigationController(rootViewController: form)
        V2NChrome.style(navigationController: nav)
        if #available(iOS 15.0, *) {
            if let sheet = nav.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
            }
        }
        present(nav, animated: true)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        collections.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "list", for: indexPath)
        var config = cell.defaultContentConfiguration()
        let item = collections[indexPath.row]
        config.text = item.title
        config.secondaryText = String(localized: "\(item.passages?.count ?? 0) versículos")
        config.v2nApplyBrandListStyle(symbol: "list.bullet.rectangle.fill")
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .default
        cell.contentConfiguration = config
        cell.v2nApplyBrandChrome()
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !collections.isEmpty else { return }
        let item = collections[indexPath.row]
        navigationController?.pushViewController(MyCollectionDetailViewController(collection: item), animated: true)
    }
}

final class MyCollectionDetailViewController: UITableViewController {
    private var collection: NativeAPIClient.UserCollectionDTO
    private let emptyState = V2NEmptyStateView()

    init(collection: NativeAPIClient.UserCollectionDTO) {
        self.collection = collection
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        v2nApplyGroupedChrome()
        title = collection.title
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "passage")
        tableView.backgroundView = emptyState
        refreshEmptyState()
    }

    private func refreshEmptyState() {
        if (collection.passages?.isEmpty ?? true) {
            emptyState.show(
                symbol: "text.book.closed",
                title: String(localized: "Lista vazia"),
                message: String(localized: "Salve um versículo em «Salvar na minha lista».")
            )
        } else {
            emptyState.hide()
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        collection.passages?.count ?? 0
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "passage", for: indexPath)
        let passage = collection.passages![indexPath.row]
        var config = cell.defaultContentConfiguration()
        let localized = BibleBookCatalog.formatPassage(
            bookId: passage.bookId,
            chapter: passage.chapter,
            verseStart: passage.verseStart,
            verseEnd: passage.verseEnd
        )
        config.text = localized
        config.v2nApplyBrandListStyle(symbol: "text.book.closed.fill")
        cell.contentConfiguration = config
        cell.v2nApplyBrandChrome()
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let passage = collection.passages?[indexPath.row] else { return }
        let localized = BibleBookCatalog.formatPassage(
            bookId: passage.bookId,
            chapter: passage.chapter,
            verseStart: passage.verseStart,
            verseEnd: passage.verseEnd
        )
        let actions = VerseActionsViewController(passage: passage, label: localized, prefs: nil)
        navigationController?.pushViewController(actions, animated: true)
    }
}
