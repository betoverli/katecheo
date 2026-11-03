import UIKit

/// Book → chapter → verse picker for inserting a `bibleRef` pill.
/// Book step reuses the Versículos abbreviation-square grid (`V2NBookAbbrCell`).
@MainActor
final class BibleRefInsertPicker: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource, UISearchResultsUpdating {
    private let onPick: (NoteDocumentCodec.BibleRefPayload) -> Void
    private var books: [NativeAPIClient.BibleBookDTO] = []
    private var filtered: [NativeAPIClient.BibleBookDTO] = []
    private let search = UISearchController(searchResultsController: nil)
    private var collectionView: UICollectionView!
    private let statusLabel = UILabel()

    private var otBooks: [NativeAPIClient.BibleBookDTO] { filtered.filter { $0.testament == "ot" } }
    private var ntBooks: [NativeAPIClient.BibleBookDTO] { filtered.filter { $0.testament == "nt" } }

    init(onPick: @escaping (NoteDocumentCodec.BibleRefPayload) -> Void) {
        self.onPick = onPick
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        V2NChrome.styleCanvas(view)
        title = String(localized: "Inserir referência")
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: String(localized: "Cancelar"),
            style: .plain,
            target: self,
            action: #selector(cancel)
        )

        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = String(localized: "Buscar livro")
        navigationItem.searchController = search
        definesPresentationContext = true

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = V2NDesign.caption()
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.text = String(localized: "Carregando…")
        statusLabel.adjustsFontForContentSizeCategory = true

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: V2NBookGridLayout.make(compact: true))
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .onDrag
        collectionView.register(V2NBookAbbrCell.self, forCellWithReuseIdentifier: V2NBookAbbrCell.reuseId)
        collectionView.register(
            V2NBookSectionHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: V2NBookSectionHeaderView.reuseId
        )

        view.addSubview(statusLabel)
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: V2NDesign.Space.xxs),
            statusLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),

            collectionView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: V2NDesign.Space.xs),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        Task { await loadBooks() }
    }

    @objc private func cancel() {
        dismiss(animated: true)
    }

    private func loadBooks() async {
        do {
            books = try await NativeAPIClient.fetchBibleBooks(locale: AppLocale.apiCode)
            applyFilter()
            statusLabel.text = String(localized: "Toque no livro")
            statusLabel.textColor = V2NDesign.accent
        } catch {
            statusLabel.text = error.localizedDescription
            statusLabel.textColor = V2NDesign.danger
            let alert = UIAlertController(title: String(localized: "Erro"), message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default) { [weak self] _ in
                self?.dismiss(animated: true)
            })
            present(alert, animated: true)
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
        collectionView.reloadData()
    }

    func updateSearchResults(for searchController: UISearchController) {
        applyFilter()
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int { 2 }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        section == 0 ? otBooks.count : ntBooks.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let book = (indexPath.section == 0 ? otBooks : ntBooks)[indexPath.item]
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: V2NBookAbbrCell.reuseId, for: indexPath) as! V2NBookAbbrCell
        cell.configure(abbr: book.abbr, accessibilityName: book.name)
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
        navigationController?.pushViewController(
            BibleRefChapterPicker(book: book, onPick: { [weak self] ref in
                self?.onPick(ref)
                self?.dismiss(animated: true)
            }),
            animated: true
        )
    }
}

@MainActor
private final class BibleRefChapterPicker: UITableViewController {
    private let book: NativeAPIClient.BibleBookDTO
    private let onPick: (NoteDocumentCodec.BibleRefPayload) -> Void

    init(book: NativeAPIClient.BibleBookDTO, onPick: @escaping (NoteDocumentCodec.BibleRefPayload) -> Void) {
        self.book = book
        self.onPick = onPick
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        v2nApplyGroupedChrome()
        title = book.name
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "chapter")
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        book.chapters
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "chapter", for: indexPath)
        var config = cell.defaultContentConfiguration()
        config.text = String(localized: "Capítulo \(indexPath.row + 1)")
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let chapter = indexPath.row + 1
        let verses = book.verses.indices.contains(indexPath.row) ? book.verses[indexPath.row] : 0
        navigationController?.pushViewController(
            BibleRefVersePicker(book: book, chapter: chapter, verseCount: verses, onPick: onPick),
            animated: true
        )
    }
}

@MainActor
private final class BibleRefVersePicker: UITableViewController {
    private let book: NativeAPIClient.BibleBookDTO
    private let chapter: Int
    private let verseCount: Int
    private let onPick: (NoteDocumentCodec.BibleRefPayload) -> Void
    private var rangeStart: Int?
    private var rangeEnd: Int?

    init(book: NativeAPIClient.BibleBookDTO, chapter: Int, verseCount: Int, onPick: @escaping (NoteDocumentCodec.BibleRefPayload) -> Void) {
        self.book = book
        self.chapter = chapter
        self.verseCount = verseCount
        self.onPick = onPick
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        v2nApplyGroupedChrome()
        title = String(localized: "\(book.abbr) \(chapter)")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: String(localized: "Capítulo inteiro"),
            style: .plain,
            target: self,
            action: #selector(wholeChapter)
        )
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "verse")
    }

    @objc private func wholeChapter() {
        finish(verseStart: nil, verseEnd: nil)
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if let rangeStart, rangeEnd == nil {
            return String(localized: "Toque no versículo final (início: \(rangeStart))")
        }
        return String(localized: "Toque para escolher · segundo toque define o intervalo")
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(verseCount, 1)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "verse", for: indexPath)
        let verse = indexPath.row + 1
        var config = cell.defaultContentConfiguration()
        config.text = String(localized: "Versículo \(verse)")
        cell.contentConfiguration = config
        let selected: Bool
        if let start = rangeStart, let end = rangeEnd {
            selected = verse >= min(start, end) && verse <= max(start, end)
        } else {
            selected = verse == rangeStart
        }
        cell.accessoryType = selected ? .checkmark : .none
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
        finish(verseStart: start, verseEnd: end == start ? start : end)
    }

    private func finish(verseStart: Int?, verseEnd: Int?) {
        let label: String
        if let verseStart {
            if let verseEnd, verseEnd != verseStart {
                label = String(localized: "\(book.name) \(chapter):\(verseStart)–\(verseEnd)")
            } else {
                label = String(localized: "\(book.name) \(chapter):\(verseStart)")
            }
        } else {
            label = String(localized: "\(book.name) \(chapter)")
        }
        onPick(NoteDocumentCodec.BibleRefPayload(
            bookId: book.id,
            chapter: chapter,
            verseStart: verseStart,
            verseEnd: verseEnd,
            text: label
        ))
    }
}
