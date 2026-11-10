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
            books = try await NativeAPIClient.fetchBibleBooks(locale: BibleBookCatalog.referenceLocale())
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
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: V2NBookAbbrCell.reuseId, for: indexPath) as? V2NBookAbbrCell else {
            return UICollectionViewCell()
        }
        cell.configure(abbr: book.abbr, accessibilityName: book.name)
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        guard let header = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind,
            withReuseIdentifier: V2NBookSectionHeaderView.reuseId,
            for: indexPath
        ) as? V2NBookSectionHeaderView else {
            return V2NBookSectionHeaderView(frame: .zero)
        }
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

/// Chapter grid — same `V2NNumberCell` / `V2NNumberGridLayout` as Ferramentas → Livros.
@MainActor
private final class BibleRefChapterPicker: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource {
    private let book: NativeAPIClient.BibleBookDTO
    private let onPick: (NoteDocumentCodec.BibleRefPayload) -> Void
    private var collectionView: UICollectionView!
    private let hintLabel = UILabel()

    init(book: NativeAPIClient.BibleBookDTO, onPick: @escaping (NoteDocumentCodec.BibleRefPayload) -> Void) {
        self.book = book
        self.onPick = onPick
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        V2NChrome.styleCanvas(view)
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
        let verses = book.verses.indices.contains(indexPath.item) ? book.verses[indexPath.item] : 0
        navigationController?.pushViewController(
            BibleRefVersePicker(book: book, chapter: chapter, verseCount: max(verses, 1), onPick: onPick),
            animated: true
        )
    }
}

/// Verse grid with range highlight — same UX as Ferramentas → Livros → capítulo.
@MainActor
private final class BibleRefVersePicker: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource {
    private let book: NativeAPIClient.BibleBookDTO
    private let chapter: Int
    private let verseCount: Int
    private let onPick: (NoteDocumentCodec.BibleRefPayload) -> Void
    private var rangeStart: Int?
    private var rangeEnd: Int?
    private var collectionView: UICollectionView!
    private let hintLabel = UILabel()

    init(book: NativeAPIClient.BibleBookDTO, chapter: Int, verseCount: Int, onPick: @escaping (NoteDocumentCodec.BibleRefPayload) -> Void) {
        self.book = book
        self.chapter = chapter
        self.verseCount = verseCount
        self.onPick = onPick
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        V2NChrome.styleCanvas(view)
        title = String(localized: "\(book.abbr) \(chapter)")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: String(localized: "Capítulo inteiro"),
            style: .plain,
            target: self,
            action: #selector(wholeChapter)
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
    }

    private func refreshHint() {
        if let rangeStart, rangeEnd == nil {
            hintLabel.text = String(localized: "Toque no versículo final (início: \(rangeStart))")
        } else {
            hintLabel.text = String(localized: "Toque para escolher · segundo toque define o intervalo")
        }
    }

    @objc private func wholeChapter() {
        finish(verseStart: nil, verseEnd: nil)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            self?.finish(verseStart: start, verseEnd: end == start ? start : end)
        }
    }

    private func finish(verseStart: Int?, verseEnd: Int?) {
        let label = BibleBookCatalog.formatPassage(
            bookId: book.id,
            chapter: chapter,
            verseStart: verseStart,
            verseEnd: verseEnd
        )
        onPick(NoteDocumentCodec.BibleRefPayload(
            bookId: book.id,
            chapter: chapter,
            verseStart: verseStart,
            verseEnd: verseEnd,
            text: label
        ))
    }
}
