import UIKit

// MARK: - Chapter picker

final class VerseChapterViewController: UITableViewController {
    private let book: NativeAPIClient.BibleBookDTO
    private let prefs: NativeAPIClient.PrefsDTO?

    init(book: NativeAPIClient.BibleBookDTO, prefs: NativeAPIClient.PrefsDTO?) {
        self.book = book
        self.prefs = prefs
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        v2nApplyGroupedChrome()
        title = book.name
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "chapter")
        _ = V2NGlassMaterial.sdkHasLiquidGlass()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        book.chapters
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "chapter", for: indexPath)
        let chapter = indexPath.row + 1
        let verseCount = book.verses.indices.contains(indexPath.row) ? book.verses[indexPath.row] : 0
        var config = cell.defaultContentConfiguration()
        config.text = "Capítulo \(chapter)"
        config.secondaryText = "\(verseCount) versículos"
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let chapter = indexPath.row + 1
        let verseCount = book.verses.indices.contains(indexPath.row) ? book.verses[indexPath.row] : 0
        let verses = VerseNumberViewController(book: book, chapter: chapter, verseCount: verseCount, prefs: prefs)
        navigationController?.pushViewController(verses, animated: true)
    }
}

// MARK: - Verse number picker (range: first tap start, second tap end)

final class VerseNumberViewController: UITableViewController {
    private let book: NativeAPIClient.BibleBookDTO
    private let chapter: Int
    private let verseCount: Int
    private let prefs: NativeAPIClient.PrefsDTO?
    private var rangeStart: Int?
    private var rangeEnd: Int?

    init(book: NativeAPIClient.BibleBookDTO, chapter: Int, verseCount: Int, prefs: NativeAPIClient.PrefsDTO?) {
        self.book = book
        self.chapter = chapter
        self.verseCount = verseCount
        self.prefs = prefs
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        v2nApplyGroupedChrome()
        title = "\(book.abbr) \(chapter)"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "verse")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Capítulo inteiro",
            style: .plain,
            target: self,
            action: #selector(selectWholeChapter)
        )
        _ = V2NGlassMaterial.sdkHasLiquidGlass()
    }

    @objc private func selectWholeChapter() {
        openActions(passage: NativeAPIClient.PassageDTO(
            bookId: book.id,
            chapter: chapter,
            verseStart: nil,
            verseEnd: nil
        ))
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if let rangeStart, rangeEnd == nil {
            return "Toque no versículo final (início: \(rangeStart))"
        }
        return "Toque para escolher · segundo toque define o intervalo"
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        verseCount
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "verse", for: indexPath)
        let verse = indexPath.row + 1
        var config = cell.defaultContentConfiguration()
        config.text = "Versículo \(verse)"
        cell.contentConfiguration = config
        let inRange: Bool
        if let start = rangeStart, let end = rangeEnd {
            let lo = min(start, end)
            let hi = max(start, end)
            inRange = verse >= lo && verse <= hi
        } else if let start = rangeStart {
            inRange = verse == start
        } else {
            inRange = false
        }
        cell.accessoryType = inRange ? .checkmark : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let verse = indexPath.row + 1
        if rangeStart == nil || rangeEnd != nil {
            rangeStart = verse
            rangeEnd = nil
            tableView.reloadData()
            return
        }
        rangeEnd = verse
        tableView.reloadData()
        let start = min(rangeStart!, rangeEnd!)
        let end = max(rangeStart!, rangeEnd!)
        openActions(passage: NativeAPIClient.PassageDTO(
            bookId: book.id,
            chapter: chapter,
            verseStart: start,
            verseEnd: end == start ? start : end
        ))
    }

    private func openActions(passage: NativeAPIClient.PassageDTO) {
        let label = formatLabel(passage)
        let actions = VerseActionsViewController(passage: passage, label: label, prefs: prefs)
        navigationController?.pushViewController(actions, animated: true)
    }

    private func formatLabel(_ passage: NativeAPIClient.PassageDTO) -> String {
        if let verseStart = passage.verseStart {
            if let verseEnd = passage.verseEnd, verseEnd != verseStart {
                return "\(book.name) \(chapter):\(verseStart)–\(verseEnd)"
            }
            return "\(book.name) \(chapter):\(verseStart)"
        }
        return "\(book.name) \(chapter)"
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
        statusLabel.font = .preferredFont(forTextStyle: .footnote)
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
                statusLabel.text = linkItem?.url ?? "Link pronto"
                tableView.reloadData()
            }
        } catch {
            await MainActor.run {
                statusLabel.text = "Link indisponível: \(error.localizedDescription)"
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
        switch row {
        case .openBible:
            config.text = "Abrir na Bíblia"
            config.secondaryText = ProfileBibleCatalog.name(for: prefs?.appId ?? "youversion")
            config.image = UIImage(systemName: "book.fill")
        case .share:
            config.text = "Compartilhar"
            config.image = UIImage(systemName: "square.and.arrow.up")
        case .copy:
            config.text = "Copiar referência"
            config.image = UIImage(systemName: "doc.on.doc")
        case .addToNote:
            config.text = "Adicionar à nota de hoje"
            config.image = UIImage(systemName: "note.text.badge.plus")
        case .saveToList:
            config.text = "Salvar na minha lista"
            config.image = UIImage(systemName: "bookmark")
        }
        cell.contentConfiguration = config
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
                presentAlert(title: "Sem link", message: "Não foi possível montar o link da Bíblia.")
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
        statusLabel.text = "Copiado: \(label)"
    }

    private func addToNote() {
        guard NativeAPIClient.hasBearer else {
            presentSignInNeeded()
            return
        }
        Task { @MainActor in
            do {
                let result = try await NativeAPIClient.appendVerse(passage)
                statusLabel.text = "Adicionado à nota: \(result.label)"
                let alert = UIAlertController(
                    title: "Na nota de hoje",
                    message: "\(result.label) foi inserido como referência (bibleRef).",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                alert.addAction(UIAlertAction(title: "Abrir nota", style: .default) { [weak self] _ in
                    self?.openNote(result.note)
                })
                present(alert, animated: true)
            } catch NativeAPIClient.APIError.unauthorized {
                presentSignInNeeded()
            } catch {
                presentAlert(title: "Não foi possível adicionar", message: error.localizedDescription)
            }
        }
    }

    private func openNote(_ note: NativeAPIClient.NoteDocument) {
        guard let tabs = tabBarController else { return }
        // Caderno is index 2 in NativeRootTabBarController.
        tabs.selectedIndex = 2
        if let nav = tabs.viewControllers?[2] as? UINavigationController {
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
                        title: "Minha lista"
                    )
                    statusLabel.text = "Salvo em «\(created.title)»"
                    return
                }
                let sheet = UIAlertController(title: "Salvar na lista", message: nil, preferredStyle: .actionSheet)
                for collection in collections {
                    sheet.addAction(UIAlertAction(title: collection.title, style: .default) { [weak self] _ in
                        self?.save(to: collection.id)
                    })
                }
                sheet.addAction(UIAlertAction(title: "Nova lista…", style: .default) { [weak self] _ in
                    self?.promptNewList()
                })
                sheet.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
                if let pop = sheet.popoverPresentationController {
                    pop.sourceView = tableView
                }
                present(sheet, animated: true)
            } catch {
                presentAlert(title: "Listas", message: error.localizedDescription)
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
                statusLabel.text = "Salvo em «\(collection.title)»"
            } catch {
                presentAlert(title: "Não foi possível salvar", message: error.localizedDescription)
            }
        }
    }

    private func promptNewList() {
        let alert = UIAlertController(title: "Nova lista", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Nome da lista" }
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
        alert.addAction(UIAlertAction(title: "Salvar", style: .default) { [weak self] _ in
            guard let self else { return }
            let title = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            Task { @MainActor in
                do {
                    let collection = try await NativeAPIClient.savePassageToCollection(
                        passage: self.passage,
                        title: (title?.isEmpty == false) ? title : "Minha lista"
                    )
                    self.statusLabel.text = "Salvo em «\(collection.title)»"
                } catch {
                    self.presentAlert(title: "Não foi possível salvar", message: error.localizedDescription)
                }
            }
        })
        present(alert, animated: true)
    }

    private func presentSignInNeeded() {
        presentAlert(title: "Entrar", message: "Inicie sessão na aba Perfil ou Caderno para salvar versículos.")
    }

    private func presentAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Themes (built-in collections)

final class ThemesHomeViewController: UITableViewController, UISearchResultsUpdating {
    private var prefs: NativeAPIClient.PrefsDTO?
    private var categories: [NativeAPIClient.CategoryCardDTO] = []
    private var themes: [NativeAPIClient.ThemeCardDTO] = []
    private var kind = "index"
    private let search = UISearchController(searchResultsController: nil)

    init(prefs: NativeAPIClient.PrefsDTO?) {
        self.prefs = prefs
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        v2nApplyGroupedChrome()
        title = "Temas"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "theme")
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = "Buscar temas"
        navigationItem.searchController = search
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(reload), for: .valueChanged)
        _ = V2NGlassMaterial.sdkHasLiquidGlass()
        reload()
    }

    @objc private func reload() {
        Task { @MainActor in
            defer { refreshControl?.endRefreshing() }
            let q = (search.searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            do {
                let result = try await NativeAPIClient.fetchThemes(query: q.isEmpty ? nil : q)
                kind = result.kind
                categories = result.categories
                themes = result.themes
                tableView.reloadData()
            } catch {
                let alert = UIAlertController(title: "Temas", message: error.localizedDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
            }
        }
    }

    func updateSearchResults(for searchController: UISearchController) {
        reload()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        themes.isEmpty ? 1 : 2
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 0 { return categories.isEmpty ? nil : "Categorias" }
        return "Temas"
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 { return max(categories.count, themes.isEmpty && categories.isEmpty ? 1 : categories.count) }
        return themes.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "theme", for: indexPath)
        var config = cell.defaultContentConfiguration()
        if indexPath.section == 0 {
            if categories.isEmpty {
                config.text = themes.isEmpty ? "Nenhum tema encontrado." : "—"
                cell.selectionStyle = .none
            } else {
                let category = categories[indexPath.row]
                config.text = category.name
                if let count = category.count {
                    config.secondaryText = "\(count) temas"
                }
                cell.accessoryType = .disclosureIndicator
            }
        } else {
            let theme = themes[indexPath.row]
            config.text = theme.name
            config.secondaryText = theme.snippet
            cell.accessoryType = .disclosureIndicator
        }
        cell.contentConfiguration = config
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
                let alert = UIAlertController(title: "Categoria", message: error.localizedDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
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
        cell.contentConfiguration = config
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
                let alert = UIAlertController(title: "Tema", message: error.localizedDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
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
        config.text = passage.label ?? passage.asPassage.labelHint
        config.secondaryText = passage.snippet
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let passage = passages[indexPath.row]
        let actions = VerseActionsViewController(
            passage: passage.asPassage,
            label: passage.label ?? passage.asPassage.labelHint,
            prefs: prefs
        )
        navigationController?.pushViewController(actions, animated: true)
    }
}

// MARK: - User collections ("Minhas listas")

final class MyCollectionsViewController: UITableViewController {
    private var collections: [NativeAPIClient.UserCollectionDTO] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        v2nApplyGroupedChrome()
        title = "Minhas listas"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "list")
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(reload), for: .valueChanged)
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Nova",
            style: .plain,
            target: self,
            action: #selector(createList)
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    @objc private func reload() {
        Task { @MainActor in
            defer { refreshControl?.endRefreshing() }
            guard NativeAPIClient.hasBearer else {
                collections = []
                tableView.reloadData()
                let alert = UIAlertController(
                    title: "Entrar",
                    message: "Inicie sessão para ver suas listas de versículos.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
                return
            }
            do {
                collections = try await NativeAPIClient.listMyCollections()
                tableView.reloadData()
            } catch {
                let alert = UIAlertController(title: "Listas", message: error.localizedDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
            }
        }
    }

    @objc private func createList() {
        let alert = UIAlertController(title: "Nova lista", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Nome" }
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
        alert.addAction(UIAlertAction(title: "Criar", style: .default) { [weak self] _ in
            let title = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !title.isEmpty else { return }
            Task { @MainActor in
                do {
                    _ = try await NativeAPIClient.createMyCollection(title: title)
                    self?.reload()
                } catch {
                    let err = UIAlertController(title: "Erro", message: error.localizedDescription, preferredStyle: .alert)
                    err.addAction(UIAlertAction(title: "OK", style: .default))
                    self?.present(err, animated: true)
                }
            }
        })
        present(alert, animated: true)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(collections.count, 1)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "list", for: indexPath)
        var config = cell.defaultContentConfiguration()
        if collections.isEmpty {
            config.text = "Nenhuma lista ainda."
            config.secondaryText = "Salve um versículo em «Salvar na minha lista»."
            cell.selectionStyle = .none
            cell.accessoryType = .none
        } else {
            let item = collections[indexPath.row]
            config.text = item.title
            config.secondaryText = "\(item.passages?.count ?? 0) versículos"
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
        }
        cell.contentConfiguration = config
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
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        collection.passages?.count ?? 0
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "passage", for: indexPath)
        let passage = collection.passages![indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = passage.labelHint
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let passage = collection.passages?[indexPath.row] else { return }
        let actions = VerseActionsViewController(passage: passage, label: passage.labelHint, prefs: nil)
        navigationController?.pushViewController(actions, animated: true)
    }
}
