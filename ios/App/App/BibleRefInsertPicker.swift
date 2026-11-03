import UIKit

/// Lightweight book → chapter → verse picker that returns a bibleRef for the note editor.
@MainActor
final class BibleRefInsertPicker: UITableViewController {
    private let onPick: (NoteDocumentCodec.BibleRefPayload) -> Void
    private var books: [NativeAPIClient.BibleBookDTO] = []
    private var filtered: [NativeAPIClient.BibleBookDTO] = []
    private let search = UISearchController(searchResultsController: nil)

    init(onPick: @escaping (NoteDocumentCodec.BibleRefPayload) -> Void) {
        self.onPick = onPick
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        v2nApplyGroupedChrome()
        title = String(localized: "Inserir referência")
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: String(localized: "Cancelar"), style: .plain, target: self, action: #selector(cancel))
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = String(localized: "Buscar livro")
        navigationItem.searchController = search
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "book")
        Task { await loadBooks() }
    }

    @objc private func cancel() {
        dismiss(animated: true)
    }

    private func loadBooks() async {
        do {
            books = try await NativeAPIClient.fetchBibleBooks(locale: AppLocale.apiCode)
            filtered = books
            tableView.reloadData()
        } catch {
            let alert = UIAlertController(title: String(localized: "Erro"), message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default) { [weak self] _ in self?.dismiss(animated: true) })
            present(alert, animated: true)
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        filtered.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "book", for: indexPath)
        let book = filtered[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = book.name
        config.secondaryText = book.abbr
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let book = filtered[indexPath.row]
        navigationController?.pushViewController(
            BibleRefChapterPicker(book: book, onPick: { [weak self] ref in
                self?.onPick(ref)
                self?.dismiss(animated: true)
            }),
            animated: true
        )
    }
}

extension BibleRefInsertPicker: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        let q = (searchController.searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty {
            filtered = books
        } else {
            filtered = books.filter {
                $0.name.lowercased().contains(q) || $0.abbr.lowercased().contains(q) || $0.id.lowercased().contains(q)
            }
        }
        tableView.reloadData()
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
