import UIKit

/// Phase 1 native notebook list: search, icon-only swipe share/delete, compose.
/// Phase 2 also reuses this screen for a group's notes (`group` scope).
final class NotebookListViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, UISearchResultsUpdating {
    /// iPad Caderno/Grupos sidebar: plain edge-to-edge rows (Notes). iPhone keeps insetGrouped.
    private let tableView: UITableView = {
        let style: UITableView.Style = PadChrome.isPad ? .plain : .insetGrouped
        return UITableView(frame: .zero, style: style)
    }()
    private let refresh = UIRefreshControl()
    private var notes: [NativeAPIClient.NoteDocument] = []
    private var filtered: [NativeAPIClient.NoteDocument] = []
    private var groupCards: [NativeAPIClient.GroupNoteCardDTO] = []
    private var filteredCards: [NativeAPIClient.GroupNoteCardDTO] = []
    private var speakers: [NativeAPIClient.SpeakerDTO] = []
    private let search = UISearchController(searchResultsController: nil)
    private let emptyState = KCEmptyStateView()
    private let statusBanner = KCStatusBanner()
    private let filterChips = KCFilterChipsView()
    private typealias NoteFilter = NotebookNoteFilter.Mode
    private var noteFilter: NoteFilter = .all
    /// Session-only multi-select filters (ANY within each set; AND across sets).
    private var selectedTags: Set<String> = []
    private var selectedSpeakerIds: Set<String> = []
    private var grantedNotes: [NativeAPIClient.NoteDocument] = []
    /// When set, this list shows notes published to the group (Phase 2).
    private var group: NativeAPIClient.GroupDTO?
    private var notificationsBell: KCNotificationsBellButton?
    /// True until the first group-notes network (or throttle hit) finishes when there was no cache.
    private var groupNotesAwaitingFirstPaint = false
    /// Bumps on every reload start; only the latest generation may apply async results.
    private var reloadGeneration = 0
    /// Note id kept selected in the iPad sidebar while its detail is open (survives reloadData).
    private var highlightedNoteId: String?

    /// Test hook — current reload generation token.
    var testing_reloadGeneration: Int { reloadGeneration }
    /// Test hook — sidebar selection id after highlight / applyFilter restore.
    var testing_highlightedNoteId: String? { highlightedNoteId }
    /// Test hook — whether the table currently has a selected row (warm state).
    var testing_hasSelectedRow: Bool { tableView.indexPathForSelectedRow != nil }

    convenience init(group: NativeAPIClient.GroupDTO) {
        self.init(nibName: nil, bundle: nil)
        self.group = group
    }

    /// Test hooks — group notes cache paint.
    var testing_groupCardsCount: Int { groupCards.count }
    var testing_firstGroupNoteTitle: String? { groupCards.first?.note.title }
    var testing_groupId: String? { group?.id }
    var testing_filteredRowCount: Int {
        isGroupMode ? filteredCards.count : filtered.count
    }

    /// Seed group note cards without waiting on the network (screenshots / unit tests).
    func testing_replaceGroupCards(_ cards: [NativeAPIClient.GroupNoteCardDTO]) {
        groupCards = cards
        notes = cards.compactMap(\.document)
        groupNotesAwaitingFirstPaint = false
        applyFilter()
    }

    /// Simulates a row tap (AppTests / CI) without reaching into private `tableView`.
    func testing_selectRow(at index: Int) {
        let path = IndexPath(row: index, section: 0)
        tableView(tableView, didSelectRowAt: path)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        KCChrome.styleScreen(view)
        title = group?.name ?? String(localized: "Caderno")
        // iPhone push: back chevron on NoteDetail must read "Caderno" (personal) / group name.
        navigationItem.backButtonTitle = group?.name ?? String(localized: "Caderno")
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always
        if let nav = navigationController {
            KCChrome.style(navigationController: nav)
        }

        var trailing: [UIBarButtonItem] = [
            UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), style: .plain, target: self, action: #selector(moreMenu)),
        ]
        // Bell only on the personal Caderno tab — never on a group's notes list.
        if group == nil {
            let bell = KCNotificationsBellButton()
            bell.addTarget(self, action: #selector(openNotificationsCenter), for: .touchUpInside)
            notificationsBell = bell
            trailing.insert(UIBarButtonItem(customView: bell), at: 0)
        }
        if group == nil || group?.canPost == true {
            trailing.insert(UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(composeNote)), at: 0)
        }
        navigationItem.rightBarButtonItems = trailing
        // Accessibility: first trailing is usually compose; ellipsis keeps its own label.
        if group == nil || group?.canPost == true {
            trailing.first?.accessibilityLabel = String(localized: "Nova nota")
        }
        trailing.first(where: { $0.action == #selector(moreMenu) })?.accessibilityLabel = String(localized: "Mais opções")
        view.accessibilityIdentifier = group == nil ? "caderno.list" : "caderno.group.list"
        refreshNotificationsBadge()

        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = group == nil ? String(localized: "Pesquisar notas") : String(localized: "Pesquisar notas do grupo")
        navigationItem.searchController = search
        // Standard iOS: search collapses while scrolling the list; pull down reveals it.
        navigationItem.hidesSearchBarWhenScrolling = true
        definesPresentationContext = true

        tableView.translatesAutoresizingMaskIntoConstraints = false
        KCChrome.styleGroupedTable(tableView)
        if PadChrome.isPad {
            // Notes-like: full-bleed rows, no inset card gutters.
            tableView.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 0)
            tableView.cellLayoutMarginsFollowReadableWidth = false
        }
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(KCNoteRowCell.self, forCellReuseIdentifier: KCNoteRowCell.reuseId)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 80
        refresh.addTarget(self, action: #selector(reload), for: .valueChanged)
        tableView.refreshControl = refresh
        // Chips stay pinned under the large title so empty/filter states never hide them.
        view.addSubview(tableView)
        view.addSubview(emptyState)

        var tableTop = view.topAnchor
        var emptyTop = view.safeAreaLayoutGuide.topAnchor
        if group == nil {
            filterChips.allowsDeselect = true
            filterChips.configure(
                chips: [
                    KCFilterChip(id: NoteFilter.all.rawValue, title: String(localized: "Tudo"), systemImage: "square.stack"),
                    KCFilterChip(id: NoteFilter.tags.rawValue, title: String(localized: "Tags"), systemImage: "number"),
                    KCFilterChip(id: NoteFilter.speakers.rawValue, title: String(localized: "Speakers"), systemImage: "person.wave.2"),
                    KCFilterChip(id: NoteFilter.shared.rawValue, title: String(localized: "Compartilhadas"), systemImage: "person.2"),
                ],
                selectedId: NoteFilter.all.rawValue
            )
            filterChips.onSelect = { [weak self] id in
                self?.handleNotebookChip(id)
            }
            view.addSubview(filterChips)
            NSLayoutConstraint.activate([
                filterChips.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: KCDesign.Space.xxs),
                filterChips.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                filterChips.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ])
            tableTop = filterChips.bottomAnchor
            emptyTop = filterChips.bottomAnchor
        }

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: tableTop, constant: group == nil ? KCDesign.Space.xxs : 0),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyState.topAnchor.constraint(equalTo: emptyTop),
            emptyState.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyState.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyState.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
        installTableHeader()

        if group == nil {
            notes = LocalNoteCache.loadNotes()
            speakers = LocalNoteCache.loadSpeakers()
        } else if let group {
            // Stale-while-revalidate: paint last known group notes immediately.
            let userId = LocalSessionCache.loadMe()?.id ?? ""
            if let cached = LocalGroupNotesCache.load(userId: userId, groupId: group.id), !cached.isEmpty {
                groupCards = cached
                notes = groupCards.compactMap { $0.document }
                groupNotesAwaitingFirstPaint = false
            } else {
                groupNotesAwaitingFirstPaint = true
            }
        }
        applyFilter()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reload),
            name: .nativeSessionDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshSharedChipDot),
            name: KCActivityStore.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshNotificationsBadge),
            name: KCNotificationsBadge.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOutboxDidFlush),
            name: .nativeOutboxDidFlush,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNoteDidChange(_:)),
            name: .nativeNoteDidChange,
            object: nil
        )
    }

    /// Patch one personal Caderno row from disk/memory — no list GET.
    /// Notifications may arrive off the main thread (outbox flush); hop to MainActor before UI.
    @objc private func handleNoteDidChange(_ notification: Notification) {
        let noteId = notification.object as? String
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.group == nil else {
                self.reload()
                return
            }
            guard let noteId, !noteId.isEmpty else {
                // Bulk / legacy import: repaint from disk without a network round-trip.
                self.adoptPersonalNotes(LocalNoteCache.loadNotes(), source: .localCache, allowingShorter: true)
                return
            }
            self.patchPersonalNote(id: noteId)
        }
    }

    /// After outbox flush, refresh personal rows from disk (already updated by upsert) — no GET.
    @objc private func handleOutboxDidFlush() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.group == nil else {
                self.reload()
                return
            }
            self.adoptPersonalNotes(LocalNoteCache.loadNotes(), source: .localCache, allowingShorter: true)
        }
    }

    private func patchPersonalNote(id: String) {
        let fromMemory: NativeAPIClient.NoteDocument? = {
            let list: [NativeAPIClient.NoteDocument]? = NativeSWR.cachedValue(.notes)
            return list?.first(where: { $0.id == id })
        }()
        guard let updated = LocalNoteCache.note(id: id) ?? fromMemory else { return }
        var next = notes
        if let index = next.firstIndex(where: { $0.id == id }) {
            next[index] = updated
        } else {
            next.insert(updated, at: 0)
        }
        next.sort(by: LocalNoteCache.compareNotesForList)
        adoptPersonalNotes(next, source: .localCache, allowingShorter: false)
    }

    private enum PersonalNotesSource {
        case localCache
        case network
    }

    /// Apply a personal (non-group) notes array. Rejects a shorter unfiltered network/cache
    /// paint unless `allowingShorter` (delete / force reconcile / explicit disk replace).
    private func adoptPersonalNotes(
        _ incoming: [NativeAPIClient.NoteDocument],
        source: PersonalNotesSource,
        allowingShorter: Bool
    ) {
        if !allowingShorter, incoming.count < notes.count {
            let disk = LocalNoteCache.loadNotes()
            let baseline = max(notes.count, disk.count)
            if incoming.count < baseline {
                // Keep the fuller list; still merge any overlapping row updates.
                var merged = disk.count >= notes.count ? disk : notes
                var byId = Dictionary(uniqueKeysWithValues: merged.map { ($0.id, $0) })
                for note in incoming { byId[note.id] = note }
                merged = Array(byId.values).sorted(by: LocalNoteCache.compareNotesForList)
                notes = merged
                applyFilter()
                return
            }
        }
        _ = source
        notes = incoming
        applyFilter()
    }

    /// Instant Caderno paint from SWR memory or disk (no await).
    private func paintPersonalNotesFromCache() {
        if let mem: [NativeAPIClient.NoteDocument] = NativeSWR.cachedValue(.notes), !mem.isEmpty {
            adoptPersonalNotes(mem, source: .localCache, allowingShorter: false)
            return
        }
        let disk = LocalNoteCache.loadNotes()
        if !disk.isEmpty {
            adoptPersonalNotes(disk, source: .localCache, allowingShorter: false)
        }
    }

    @objc private func refreshSharedChipDot() {
        refreshFilterChrome()
    }

    @objc private func refreshNotificationsBadge() {
        notificationsBell?.updateBadge(KCNotificationsBadge.displayText)
    }

    @objc private func appDidBecomeActive() {
        guard group == nil else { return }
        Task { await KCNotificationsBadge.refreshFromServer() }
    }

    @objc private func openNotificationsCenter() {
        KCHaptics.selection()
        navigationController?.pushViewController(NotificationsCenterViewController(), animated: true)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Keep large titles consistent with Grupos / Ferramentas / Perfil (TF 499).
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always
        refreshNotificationsBadge()
        // Paint the full disk/memory list immediately so popping the editor never flashes
        // a truncated intermediate state while a refetch is in flight.
        if group == nil {
            paintPersonalNotesFromCache()
        }
        Task { @MainActor in
            if !NativeAPIClient.hasBearer {
                _ = await NativeSessionBootstrap.migrateCookieToKeychainIfNeeded()
            }
            if group == nil {
                await KCNotificationsBadge.refreshFromServer()
            }
            reload()
        }
    }

    @objc private func reload() {
        reloadGeneration &+= 1
        let generation = reloadGeneration
        Task { @MainActor in
            defer {
                if generation == reloadGeneration {
                    refresh.endRefreshing()
                }
            }
            guard NativeAPIClient.hasBearer else {
                guard generation == reloadGeneration else { return }
                if group != nil {
                    groupNotesAwaitingFirstPaint = false
                    groupCards = []
                    applyFilter()
                    setBannerStatus(String(localized: "Faça login para ver as notas do grupo."), kind: .warning)
                    showEmpty(
                        symbol: "person.badge.key",
                        title: String(localized: "Entre para sincronizar"),
                        message: String(localized: "As notas deste grupo ficam disponíveis após o login."),
                        actionTitle: String(localized: "Entrar")
                    )
                    return
                }
                adoptPersonalNotes(LocalNoteCache.loadNotes(), source: .localCache, allowingShorter: true)
                setBannerStatus(
                    notes.isEmpty ? String(localized: "Faça login para sincronizar o caderno.") : String(localized: "Offline / sem sessão — cache local."),
                    kind: notes.isEmpty ? .warning : .neutral
                )
                if notes.isEmpty {
                    showEmpty(
                        symbol: "note.text",
                        title: String(localized: "Seu caderno está vazio"),
                        message: String(localized: "Entre para sincronizar suas anotações."),
                        actionTitle: String(localized: "Entrar")
                    )
                }
                if notes.isEmpty, presentedViewController == nil, !OnboardingStore.shouldSkipAutoSignIn {
                    showSignIn(auto: true)
                }
                return
            }
            do {
                let force = refresh.isRefreshing
                if let group {
                    let userId = LocalSessionCache.loadMe()?.id ?? ""
                    // Keep showing cache while revalidating; spinner only when nothing cached yet.
                    if groupCards.isEmpty,
                       let cached = LocalGroupNotesCache.load(userId: userId, groupId: group.id),
                       !cached.isEmpty
                    {
                        groupCards = cached
                        notes = groupCards.compactMap { $0.document }
                        groupNotesAwaitingFirstPaint = false
                        applyFilter()
                    } else if groupCards.isEmpty {
                        groupNotesAwaitingFirstPaint = true
                        emptyState.showLoading(message: String(localized: "Carregando…"))
                        tableView.isHidden = true
                    }

                    let notesFresh = NativeSWR.isFresh(.groupNotes(group.id), ttl: NativeSWR.TTL.groupNotes)
                    if force || !notesFresh {
                        // Metadata refresh only when we actually hit the notes endpoint (or pull).
                        let refreshed = try await NativeAPIClient.getGroup(id: group.id)
                        guard generation == reloadGeneration else { return }
                        self.group = refreshed
                        title = refreshed.name
                        groupCards = try await NativeAPIClient.listGroupNotes(groupId: group.id, force: force)
                        guard generation == reloadGeneration else { return }
                        notes = groupCards.compactMap { $0.document }
                    } else if let cached = LocalGroupNotesCache.load(userId: userId, groupId: group.id) {
                        // Throttled — reuse disk/memory without another GET.
                        guard generation == reloadGeneration else { return }
                        groupCards = cached
                        notes = groupCards.compactMap { $0.document }
                    }
                    guard generation == reloadGeneration else { return }
                    groupNotesAwaitingFirstPaint = false
                    // No persistent sync success banner — list content is enough.
                    setBannerStatus(nil)
                    applyFilter()
                    return
                }

                // Personal Caderno: paint cache first; skip list refetch when SWR memory is fresh.
                paintPersonalNotesFromCache()
                let notesFresh = NativeSWR.isFresh(.notes, ttl: NativeSWR.TTL.lists)
                if force || !notesFresh {
                    async let remoteNotes = NativeAPIClient.listNotes(force: force)
                    async let remoteSpeakers = NativeAPIClient.listSpeakers(force: force)
                    async let remoteGranted = NativeAPIClient.listGrantedNotes(force: force)
                    let fetchedNotes = try await remoteNotes
                    let fetchedSpeakers = try await remoteSpeakers
                    let fetchedGranted = (try? await remoteGranted) ?? []
                    guard generation == reloadGeneration else { return }
                    speakers = fetchedSpeakers
                    grantedNotes = fetchedGranted
                    // Full listNotes merge is authoritative (may shrink after real server deletes).
                    adoptPersonalNotes(fetchedNotes, source: .network, allowingShorter: true)
                    let offline = NativeSWR.consumeOfflineFallback(.notes)
                    if offline {
                        setBannerStatus(Self.offlineCacheBanner(pending: NativeOutbox.pendingCount), kind: .warning)
                    } else {
                        setBannerStatus(nil)
                    }
                    Task { await KCActivitySync.refreshFromServer(force: force) }
                } else {
                    // In-memory list is current — refresh speakers/granted only if stale, no notes GET.
                    async let remoteSpeakers = NativeAPIClient.listSpeakers(force: false)
                    async let remoteGranted = NativeAPIClient.listGrantedNotes(force: false)
                    speakers = (try? await remoteSpeakers) ?? speakers
                    grantedNotes = (try? await remoteGranted) ?? grantedNotes
                    guard generation == reloadGeneration else { return }
                    setBannerStatus(nil)
                    applyFilter()
                }
            } catch NativeAPIClient.APIError.unauthorized {
                guard generation == reloadGeneration else { return }
                groupNotesAwaitingFirstPaint = false
                setBannerStatus(String(localized: "Sessão expirada. Entre novamente."), kind: .error)
                if group == nil {
                    adoptPersonalNotes(LocalNoteCache.loadNotes(), source: .localCache, allowingShorter: true)
                }
                applyFilter()
                showEmpty(
                    symbol: "exclamationmark.shield",
                    title: String(localized: "Sessão expirada"),
                    message: String(localized: "Entre de novo para continuar sincronizando."),
                    actionTitle: String(localized: "Entrar")
                )
                if !OnboardingStore.shouldSkipAutoSignIn {
                    showSignIn(auto: true)
                }
            } catch {
                guard generation == reloadGeneration else { return }
                groupNotesAwaitingFirstPaint = false
                if group == nil {
                    adoptPersonalNotes(LocalNoteCache.loadNotes(), source: .localCache, allowingShorter: true)
                    setBannerStatus(Self.offlineCacheBanner(pending: NativeOutbox.pendingCount), kind: .warning)
                } else {
                    if groupCards.isEmpty {
                        setBannerStatus(String(localized: "Sem rede. \(error.localizedDescription)"), kind: .error)
                    } else {
                        setBannerStatus(String(localized: "Sem rede — mostrando cache."), kind: .warning)
                    }
                }
                applyFilter()
            }
        }
    }

    /// Test hook — bump generation and report whether a stale token must be ignored.
    func testing_beginReloadGeneration() -> Int {
        reloadGeneration &+= 1
        return reloadGeneration
    }

    func testing_shouldApplyReload(generation: Int) -> Bool {
        generation == reloadGeneration
    }

    private var isGroupMode: Bool { group != nil }

    /// Offline Caderno banner — uses catalog keys with en/es (and plural-friendly pending count).
    private static func offlineCacheBanner(pending: Int) -> String {
        if pending > 0 {
            return String(localized: "Sem rede — mostrando cache · \(pending) pendente(s).")
        }
        return String(localized: "Sem rede — mostrando cache.")
    }

    /// Status banner stays in the table header; Caderno chips are pinned above the table.
    private func installTableHeader() {
        // Use the list/column width — never UIScreen (wrong in iPad split / Stage Manager).
        let width = max(view.bounds.width, tableView.bounds.width, 1)
        let header = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 1))
        header.backgroundColor = .clear

        statusBanner.removeFromSuperview()
        statusBanner.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(statusBanner)
        let hasText = !(statusBanner.text?.isEmpty ?? true)
        let bannerHeight = hasText
            ? statusBanner.heightAnchor.constraint(greaterThanOrEqualToConstant: 18)
            : statusBanner.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            statusBanner.topAnchor.constraint(equalTo: header.topAnchor, constant: hasText ? KCDesign.Space.xxs : 0),
            statusBanner.leadingAnchor.constraint(equalTo: header.layoutMarginsGuide.leadingAnchor),
            statusBanner.trailingAnchor.constraint(equalTo: header.layoutMarginsGuide.trailingAnchor),
            bannerHeight,
            statusBanner.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: hasText ? -KCDesign.Space.xxs : 0),
        ])

        header.setNeedsLayout()
        header.layoutIfNeeded()
        let height = header.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        header.frame = CGRect(x: 0, y: 0, width: width, height: max(height, hasText ? 1 : 0.5))
        tableView.tableHeaderView = header
    }

    private func setBannerStatus(_ text: String?, kind: KCStatusBanner.Kind = .neutral) {
        statusBanner.setStatus(text, kind: kind)
        installTableHeader()
    }

    private func showEmpty(symbol: String, title: String, message: String, actionTitle: String? = nil) {
        emptyState.show(
            symbol: symbol,
            title: title,
            message: message,
            actionTitle: actionTitle,
            action: actionTitle != nil ? { [weak self] in self?.presentSignInTapped() } : nil
        )
        // Keep the table (and its chip header) visible so Caderno pills never disappear.
        // Empty state overlays the rows; only hide the table in group mode without chips.
        if isGroupMode {
            tableView.isHidden = true
        } else {
            tableView.isHidden = false
            tableView.backgroundView = nil
        }
    }

    private func hideEmpty() {
        emptyState.hide()
        tableView.isHidden = false
    }

    private func refreshSharedActivity() {
        refreshFilterChrome()
    }

    /// Badges + titles reflect active multi-select filters; shared unread keeps its dot.
    private func refreshFilterChrome() {
        guard group == nil else { return }
        var badged = Set<String>()
        if KCActivityStore.sharedChipDot {
            badged.insert(NoteFilter.shared.rawValue)
        }
        if !selectedTags.isEmpty {
            badged.insert(NoteFilter.tags.rawValue)
        }
        if !selectedSpeakerIds.isEmpty {
            badged.insert(NoteFilter.speakers.rawValue)
        }
        let tagsTitle: String
        if selectedTags.isEmpty {
            tagsTitle = String(localized: "Tags")
        } else {
            tagsTitle = "\(String(localized: "Tags")) (\(selectedTags.count))"
        }
        let speakersTitle: String
        if selectedSpeakerIds.isEmpty {
            speakersTitle = String(localized: "Speakers")
        } else {
            speakersTitle = "\(String(localized: "Speakers")) (\(selectedSpeakerIds.count))"
        }
        filterChips.configure(
            chips: [
                KCFilterChip(id: NoteFilter.all.rawValue, title: String(localized: "Tudo"), systemImage: "square.stack"),
                KCFilterChip(id: NoteFilter.tags.rawValue, title: tagsTitle, systemImage: "number"),
                KCFilterChip(id: NoteFilter.speakers.rawValue, title: speakersTitle, systemImage: "person.wave.2"),
                KCFilterChip(id: NoteFilter.shared.rawValue, title: String(localized: "Compartilhadas"), systemImage: "person.2"),
            ],
            selectedId: noteFilter.rawValue,
            badgedIds: badged
        )
    }

    private func applyFilter() {
        refreshSharedActivity()
        let q = (search.searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if isGroupMode {
            if q.isEmpty {
                filteredCards = groupCards
            } else {
                filteredCards = groupCards.filter { card in
                    if card.note.title.lowercased().contains(q) { return true }
                    if card.note.happenedAt.contains(q) { return true }
                    if card.author.displayName.lowercased().contains(q) { return true }
                    if let doc = card.document, doc.preview.lowercased().contains(q) { return true }
                    return false
                }
            }
            if filteredCards.isEmpty {
                if groupNotesAwaitingFirstPaint && q.isEmpty {
                    // First open with no cache — keep the loading spinner, don't flash empty.
                    emptyState.showLoading(message: String(localized: "Carregando…"))
                    tableView.isHidden = true
                } else if q.isEmpty {
                    showEmpty(
                        symbol: "tray",
                        title: String(localized: "Nenhuma nota neste grupo"),
                        message: String(localized: "Toque em + para criar uma nota neste grupo, ou peça para alguém compartilhar.")
                    )
                } else {
                    showEmpty(symbol: "magnifyingglass", title: String(localized: "Nenhum resultado"), message: String(localized: "Tente outro termo de busca."))
                }
            } else {
                hideEmpty()
            }
            tableView.reloadData()
            restoreHighlightedSelection()
            return
        }
        let source = NotebookNoteFilter.filterNotes(
            notes,
            mode: noteFilter,
            selectedTags: selectedTags,
            selectedSpeakerIds: selectedSpeakerIds,
            grantedNotes: grantedNotes
        )
        if q.isEmpty {
            filtered = source
        } else {
            filtered = source.filter { note in
                if note.title.lowercased().contains(q) { return true }
                if note.tags.contains(where: { $0.lowercased().contains(q) }) { return true }
                if note.happenedAt.contains(q) { return true }
                if note.preview.lowercased().contains(q) { return true }
                return false
            }
        }
        if filtered.isEmpty {
            if !NativeAPIClient.hasBearer && notes.isEmpty {
                showEmpty(
                    symbol: "note.text",
                    title: String(localized: "Seu caderno está vazio"),
                    message: String(localized: "Entre para sincronizar suas anotações."),
                    actionTitle: String(localized: "Entrar")
                )
            } else if NativeAPIClient.hasBearer || !notes.isEmpty {
                if q.isEmpty {
                    showEmpty(
                        symbol: "square.and.pencil",
                        title: String(localized: "Nenhuma nota ainda"),
                        message: String(localized: "Toque em + para criar a primeira.")
                    )
                } else {
                    showEmpty(symbol: "magnifyingglass", title: String(localized: "Nenhum resultado"), message: String(localized: "Tente outro termo de busca."))
                }
            }
        } else {
            hideEmpty()
        }
        tableView.reloadData()
        restoreHighlightedSelection()
    }

    func updateSearchResults(for searchController: UISearchController) {
        applyFilter()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        isGroupMode ? filteredCards.count : filtered.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: KCNoteRowCell.reuseId, for: indexPath) as? KCNoteRowCell else {
            return UITableViewCell()
        }
        if isGroupMode {
            let card = filteredCards[indexPath.row]
            let title = card.note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "Reunião") : card.note.title
            let preview = card.document?.listBodyPreview ?? ""
            let subtitle = preview.isEmpty ? (card.author.displayName) : preview
            let day = AppLocale.relativeNoteDay(card.note.happenedAt)
            let speakerName = mainSpeakerName(for: card.document)
            cell.configure(
                title: title,
                subtitle: subtitle,
                tags: card.document?.tags ?? [],
                speakerName: speakerName,
                date: day
            )
            cell.applySidebarStyle(isPadSidebar: PadChrome.isPad)
            return cell
        }
        let note = filtered[indexPath.row]
        let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "Reunião") : note.title
        let day = AppLocale.relativeNoteDay(note.happenedAt)
        let speakerName = mainSpeakerName(for: note)
        cell.configure(
            title: title,
            subtitle: note.listBodyPreview,
            tags: note.tags,
            speakerName: speakerName,
            date: day
        )
        cell.applySidebarStyle(isPadSidebar: PadChrome.isPad)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        KCHaptics.selection()
        if isGroupMode {
            let card = filteredCards[indexPath.row]
            guard card.owned, let doc = card.document else {
                tableView.deselectRow(at: indexPath, animated: true)
                presentGroupNoteActions(card, at: indexPath)
                return
            }
            // List title comes from NoteMeta — merge it when the cached document is sparse
            // (tags/speaker present, title/body empty) so the editor never opens blank.
            var initial = LocalNoteCache.preferredNote(over: doc)
            let metaTitle = card.note.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if initial.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !metaTitle.isEmpty {
                initial.title = metaTitle
            }
            let detail = NoteDetailViewController(noteId: initial.id, initial: initial)
            openNoteDetail(detail, keepingSelectionAt: indexPath)
            return
        }
        let note = filtered[indexPath.row]
        let isGranted = noteFilter == .shared || grantedNotes.contains(where: { $0.id == note.id })
        if isGranted {
            KCActivityStore.markSharedNoteOpened(note.id)
        }
        // Owned notes open from disk so offline edits survive list→detail round-trips.
        let initial = isGranted ? note : LocalNoteCache.preferredNote(over: note)
        let detail = NoteDetailViewController(
            noteId: note.id,
            initial: initial,
            grantedReadOnly: isGranted,
            sharedAuthorUserId: nil,
            sharedAuthorName: isGranted ? String(localized: "Nota compartilhada") : nil
        )
        openNoteDetail(detail, keepingSelectionAt: indexPath)
    }

    /// iPad split: show in detail column. iPhone / no split: push (pre-#131).
    private func openNoteDetail(_ detail: NoteDetailViewController, keepingSelectionAt indexPath: IndexPath?) {
        // Never route through a split on iPhone — navigationController push only.
        if NotebookChrome.prefersSplit, let split = notebookSplit {
            let regular = traitCollection.horizontalSizeClass == .regular && !split.isCollapsed
            if regular, let indexPath {
                tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
            } else if let indexPath {
                tableView.deselectRow(at: indexPath, animated: true)
            }
            split.showNote(detail, animated: true)
            return
        }
        if PadChrome.isPad, let groupsSplit = groupsSplit {
            let regular = traitCollection.horizontalSizeClass == .regular && !groupsSplit.isCollapsed
            if regular, let indexPath {
                tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
            } else if let indexPath {
                tableView.deselectRow(at: indexPath, animated: true)
            }
            groupsSplit.showNote(detail, animated: true)
            return
        }
        if let indexPath {
            tableView.deselectRow(at: indexPath, animated: true)
        }
        detail.hidesBottomBarWhenPushed = true
        guard let nav = navigationController else {
            assertionFailure("Caderno list must sit in a UINavigationController on iPhone")
            return
        }
        nav.pushViewController(detail, animated: true)
    }

    private var notebookSplit: NotebookSplitViewController? {
        if let split = splitViewController as? NotebookSplitViewController { return split }
        var parent: UIViewController? = self.parent
        while let current = parent {
            if let split = current as? NotebookSplitViewController { return split }
            parent = current.parent
        }
        return nil
    }

    private var groupsSplit: GroupsSplitViewController? {
        if let split = splitViewController as? GroupsSplitViewController { return split }
        var parent: UIViewController? = self.parent
        while let current = parent {
            if let split = current as? GroupsSplitViewController { return split }
            parent = current.parent
        }
        return nil
    }

    /// Highlight the open note in the list (split regular width).
    func highlightSelectedNote(id: String?) {
        highlightedNoteId = id
        restoreHighlightedSelection()
    }

    /// Re-apply warm selection after `reloadData` (which clears UITableView selection).
    private func restoreHighlightedSelection() {
        guard PadChrome.isPad else {
            if let selected = tableView.indexPathForSelectedRow {
                tableView.deselectRow(at: selected, animated: false)
            }
            return
        }
        guard let id = highlightedNoteId else {
            if let selected = tableView.indexPathForSelectedRow {
                tableView.deselectRow(at: selected, animated: true)
            }
            return
        }
        let path: IndexPath?
        if isGroupMode {
            path = filteredCards.firstIndex(where: { $0.note.id == id }).map { IndexPath(row: $0, section: 0) }
        } else {
            path = filtered.firstIndex(where: { $0.id == id }).map { IndexPath(row: $0, section: 0) }
        }
        guard let path else {
            if let selected = tableView.indexPathForSelectedRow {
                tableView.deselectRow(at: selected, animated: true)
            }
            return
        }
        tableView.selectRow(at: path, animated: false, scrollPosition: .none)
        if let cell = tableView.cellForRow(at: path) {
            cell.setSelected(true, animated: false)
            cell.setNeedsUpdateConfiguration()
        }
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        if isGroupMode {
            let card = filteredCards[indexPath.row]
            guard card.owned || group?.isAdmin == true else { return nil }
            let remove = UIContextualAction.kcIconOnly(
                style: .destructive,
                systemName: "folder.badge.minus",
                accessibilityLabel: String(localized: "Retirar")
            ) { [weak self] _, view, done in
                self?.confirmUnpublish(card, from: view, at: indexPath) { done($0) }
            }
            return UISwipeActionsConfiguration(actions: [remove])
        }
        let note = filtered[indexPath.row]
        // Granted (Compartilhadas) notes are not owned — no delete.
        if noteFilter == .shared || grantedNotes.contains(where: { $0.id == note.id && !notes.contains(where: { $0.id == note.id }) }) {
            return nil
        }
        let delete = UIContextualAction.kcIconOnly(
            style: .destructive,
            systemName: "trash",
            accessibilityLabel: String(localized: "Excluir")
        ) { [weak self] _, view, done in
            self?.confirmDelete(note, from: view, at: indexPath) { done($0) }
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        if isGroupMode {
            let card = filteredCards[indexPath.row]
            guard !card.owned else { return nil }
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
                guard let self else { return UIMenu(children: []) }
                let report = UIAction(
                    title: String(localized: "Denunciar"),
                    image: UIImage(systemName: "exclamationmark.bubble")
                ) { [weak self] _ in
                    guard let self else { return }
                    ReportBlockSupport.presentReport(
                        target: .note(
                            noteId: card.note.id,
                            authorUserId: card.author.userId,
                            authorName: card.author.displayName
                        ),
                        from: self,
                        sourceView: self.tableView,
                        sourceRect: self.tableView.rectForRow(at: indexPath)
                    )
                }
                var children: [UIMenuElement] = [report]
                if !card.author.userId.isEmpty {
                    let block = UIAction(
                        title: String(localized: "Bloquear"),
                        image: UIImage(systemName: "hand.raised"),
                        attributes: .destructive
                    ) { [weak self] _ in
                        guard let self else { return }
                        ReportBlockSupport.confirmBlock(
                            userId: card.author.userId,
                            displayName: card.author.displayName,
                            from: self,
                            sourceView: self.tableView,
                            sourceRect: self.tableView.rectForRow(at: indexPath)
                        ) {
                            self.groupCards.removeAll { $0.author.userId == card.author.userId }
                            self.applyFilter()
                        }
                    }
                    children.append(block)
                }
                return UIMenu(children: children)
            }
        }
        let note = filtered[indexPath.row]
        let isGranted = noteFilter == .shared || grantedNotes.contains(where: { $0.id == note.id })
        guard isGranted else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return UIMenu(children: []) }
            let report = UIAction(
                title: String(localized: "Denunciar"),
                image: UIImage(systemName: "exclamationmark.bubble")
            ) { [weak self] _ in
                guard let self else { return }
                ReportBlockSupport.presentReport(
                    target: .note(
                        noteId: note.id,
                        authorUserId: nil,
                        authorName: String(localized: "Nota compartilhada")
                    ),
                    from: self,
                    sourceView: self.tableView,
                    sourceRect: self.tableView.rectForRow(at: indexPath)
                )
            }
            return UIMenu(children: [report])
        }
    }

    func tableView(
        _ tableView: UITableView,
        leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        if isGroupMode {
            guard let doc = filteredCards[indexPath.row].document else { return nil }
            let share = UIContextualAction.kcIconOnly(
                style: .normal,
                systemName: "square.and.arrow.up",
                accessibilityLabel: String(localized: "Compartilhar"),
                backgroundColor: KCDesign.bookmark
            ) { [weak self] _, view, done in
                self?.share(doc, from: view)
                done(true)
            }
            return UISwipeActionsConfiguration(actions: [share])
        }
        let note = filtered[indexPath.row]
        let share = UIContextualAction.kcIconOnly(
            style: .normal,
            systemName: "square.and.arrow.up",
            accessibilityLabel: String(localized: "Compartilhar"),
            backgroundColor: KCDesign.bookmark
        ) { [weak self] _, view, done in
            self?.share(note, from: view)
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [share])
    }

    private func presentGroupNoteActions(_ card: NativeAPIClient.GroupNoteCardDTO, at indexPath: IndexPath) {
        let title = card.note.title.isEmpty ? String(localized: "Reunião") : card.note.title
        let sheet = UIAlertController(
            title: title,
            message: String(localized: "Nota de \(card.author.displayName). Só o autor pode editar nesta tela nativa."),
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: String(localized: "Denunciar"), style: .default) { [weak self] _ in
            guard let self else { return }
            ReportBlockSupport.presentReport(
                target: .note(
                    noteId: card.note.id,
                    authorUserId: card.author.userId,
                    authorName: card.author.displayName
                ),
                from: self,
                sourceView: self.tableView,
                sourceRect: self.tableView.rectForRow(at: indexPath)
            )
        })
        if !card.author.userId.isEmpty {
            sheet.addAction(UIAlertAction(title: String(localized: "Bloquear"), style: .destructive) { [weak self] _ in
                guard let self else { return }
                ReportBlockSupport.confirmBlock(
                    userId: card.author.userId,
                    displayName: card.author.displayName,
                    from: self,
                    sourceView: self.tableView,
                    sourceRect: self.tableView.rectForRow(at: indexPath)
                ) {
                    self.groupCards.removeAll { $0.author.userId == card.author.userId }
                    self.applyFilter()
                }
            })
        }
        sheet.addAction(UIAlertAction(title: String(localized: "OK"), style: .cancel))
        KCConfirmation.presentActionSheet(
            sheet,
            from: self,
            sourceView: tableView,
            sourceRect: tableView.rectForRow(at: indexPath)
        )
    }

    private func confirmUnpublish(
        _ card: NativeAPIClient.GroupNoteCardDTO,
        from source: UIView?,
        at indexPath: IndexPath,
        completion: @escaping (Bool) -> Void
    ) {
        guard let group else {
            completion(false)
            return
        }
        let alert = UIAlertController(title: nil, message: String(localized: "Retirar esta nota do grupo?"), preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: String(localized: "Cancelar"), style: .cancel) { _ in completion(false) })
        alert.addAction(UIAlertAction(title: String(localized: "Retirar do grupo"), style: .destructive) { [weak self] _ in
            Task { @MainActor in
                do {
                    try await NativeAPIClient.unpublishNote(noteId: card.note.id, fromGroupId: group.id)
                    self?.groupCards.removeAll { $0.note.id == card.note.id }
                    self?.applyFilter()
                    KCHaptics.success()
                    completion(true)
                } catch {
                    completion(false)
                    let err = UIAlertController(title: String(localized: "Erro"), message: error.localizedDescription, preferredStyle: .alert)
                    err.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
                    self?.present(err, animated: true)
                }
            }
        })
        presentActionSheet(alert, from: source, at: indexPath)
    }

    private func confirmDelete(
        _ note: NativeAPIClient.NoteDocument,
        from source: UIView?,
        at indexPath: IndexPath,
        completion: @escaping (Bool) -> Void
    ) {
        let alert = UIAlertController(title: nil, message: String(localized: "Excluir esta nota?"), preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: String(localized: "Cancelar"), style: .cancel) { _ in completion(false) })
        alert.addAction(UIAlertAction(title: String(localized: "Excluir nota"), style: .destructive) { [weak self] _ in
            Task { @MainActor in
                do {
                    if LocalNoteCache.isAwaitingFirstSync(note.id) {
                        NativeAPIClient.discardLocalOnlyNote(id: note.id)
                    } else if NativeAPIClient.hasBearer {
                        try await NativeAPIClient.deleteNote(id: note.id)
                    } else {
                        LocalNoteCache.removeNote(id: note.id)
                        NativeOutbox.enqueueNoteDelete(id: note.id)
                    }
                    self?.notes.removeAll { $0.id == note.id }
                    self?.groupCards.removeAll { $0.note.id == note.id }
                    self?.applyFilter()
                    KCHaptics.medium()
                    completion(true)
                } catch {
                    if LocalNoteCache.isAwaitingFirstSync(note.id) {
                        NativeAPIClient.discardLocalOnlyNote(id: note.id)
                    } else {
                        LocalNoteCache.removeNote(id: note.id)
                        NativeOutbox.enqueueNoteDelete(id: note.id)
                    }
                    self?.notes.removeAll { $0.id == note.id }
                    self?.groupCards.removeAll { $0.note.id == note.id }
                    self?.applyFilter()
                    completion(true)
                }
            }
        })
        presentActionSheet(alert, from: source, at: indexPath)
    }

    /// iPhone: bottom action sheet. iPad: popover anchored to the swiped row/action.
    private func presentActionSheet(_ alert: UIAlertController, from source: UIView?, at indexPath: IndexPath) {
        if let source {
            KCConfirmation.presentActionSheet(alert, from: self, sourceView: source, sourceRect: source.bounds)
        } else {
            KCConfirmation.presentActionSheet(
                alert,
                from: self,
                sourceView: tableView,
                sourceRect: tableView.rectForRow(at: indexPath)
            )
        }
    }

    private func share(_ note: NativeAPIClient.NoteDocument, from source: UIView) {
        if LocalNoteCache.isAwaitingFirstSync(note.id) {
            let alert = UIAlertController(
                title: nil,
                message: String(localized: "Disponível após sincronizar."),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
            present(alert, animated: true)
            return
        }
        let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "Reunião") : note.title
        let text = note.preview
        let url = NativeAPIClient.baseURL.appendingPathComponent("n/\(note.id)")
        let vc = UIActivityViewController(activityItems: [title, text, url], applicationActivities: nil)
        KCConfirmation.presentActivity(vc, from: self, sourceView: source, sourceRect: source.bounds)
    }

    @objc private func composeNote() {
        KCHaptics.light()
        Task { @MainActor in
            guard NativeAPIClient.hasBearer else {
                showSignIn(auto: false)
                return
            }
            // Local-first: same path online or offline. Keep emptyNote()'s 32-hex id (no temp/remap).
            let draft = NativeAPIClient.emptyNote()
            let created = LocalNoteCache.recordLocalEdit(
                draft,
                publishGroupId: group?.id,
                awaitingFirstSync: true
            )
            if let group {
                insertCreatedGroupNoteLocally(created, group: group)
            } else {
                notes.insert(created, at: 0)
                applyFilter()
            }
            let detail = NoteDetailViewController(
                noteId: created.id,
                initial: created,
                publishGroupId: group?.id
            )
            openNoteDetail(detail, keepingSelectionAt: IndexPath(row: 0, section: 0))

            // Best-effort first sync; outbox covers offline / failure.
            do {
                _ = try await NativeAPIClient.upsertNote(created, publishToGroupId: group?.id)
                NotificationCenter.default.post(name: .nativeNoteDidChange, object: created.id)
            } catch NativeAPIClient.APIError.http(let code, _) where code == 409 {
                LocalNoteCache.markSyncLimitReached(id: created.id)
            } catch {
                LocalNoteCache.markPendingSync(id: created.id)
                NativeOutbox.enqueueNoteUpsert(created, publishToGroupId: group?.id)
            }
        }
    }

    /// Paint the new note in the group list immediately (disk/SWR already updated by upsert).
    private func insertCreatedGroupNoteLocally(_ note: NativeAPIClient.NoteDocument, group: NativeAPIClient.GroupDTO) {
        // upsert(publishToGroupId:) already mirrored the card; re-read so the table matches disk.
        if let userId = LocalSessionCache.loadMe()?.id,
           let cached = LocalGroupNotesCache.load(userId: userId, groupId: group.id),
           !cached.isEmpty
        {
            groupCards = cached
        } else {
            NativeAPIClient.rememberPublishedNote(note, inGroupId: group.id)
            if let userId = LocalSessionCache.loadMe()?.id,
               let cached = LocalGroupNotesCache.load(userId: userId, groupId: group.id)
            {
                groupCards = cached
            }
        }
        notes = groupCards.compactMap(\.document)
        groupNotesAwaitingFirstPaint = false
        applyFilter()
    }

    @objc private func moreMenu() {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: String(localized: "Atualizar"), style: .default) { [weak self] _ in self?.reload() })
        if let group, group.isAccepted {
            sheet.addAction(UIAlertAction(title: String(localized: "Membros"), style: .default) { [weak self] _ in
                self?.openGroupMembers()
            })
            sheet.addAction(UIAlertAction(title: String(localized: "Convidar amigos"), style: .default) { [weak self] _ in
                self?.openInviteFriends()
            })
            sheet.addAction(UIAlertAction(title: String(localized: "Compartilhar link"), style: .default) { [weak self] _ in
                self?.shareGroupInvite()
            })
        }
        if let group, group.isAdmin {
            sheet.addAction(UIAlertAction(title: String(localized: "Renomear grupo…"), style: .default) { [weak self] _ in
                self?.promptRenameGroup()
            })
            sheet.addAction(UIAlertAction(title: String(localized: "Excluir grupo…"), style: .destructive) { [weak self] _ in
                self?.confirmDeleteGroup()
            })
        }
        if !isGroupMode {
            sheet.addAction(UIAlertAction(title: String(localized: "Speakers…"), style: .default) { [weak self] _ in
                let picker = SpeakerPickerViewController(mode: .manage, onManaged: { [weak self] in
                    self?.reload()
                })
                let nav = UINavigationController(rootViewController: picker)
                self?.present(nav, animated: true)
            })
            if NativeAPIClient.hasBearer {
                sheet.addAction(UIAlertAction(title: String(localized: "Sair"), style: .destructive) { [weak self] _ in
                    Task { @MainActor in
                        await NativeLoginService.shared.signOut()
                        self?.notes = LocalNoteCache.loadNotes()
                        self?.applyFilter()
                        self?.showSignIn(auto: false)
                    }
                })
            } else {
                sheet.addAction(UIAlertAction(title: String(localized: "Entrar"), style: .default) { [weak self] _ in
                    self?.showSignIn(auto: false)
                })
            }
        }
        sheet.addAction(UIAlertAction(title: String(localized: "Cancelar"), style: .cancel))
        KCConfirmation.presentActionSheet(
            sheet,
            from: self,
            barButtonItem: navigationItem.rightBarButtonItems?.last
        )
    }

    private func promptRenameGroup() {
        guard let group else { return }
        let alert = UIAlertController(title: String(localized: "Renomear grupo"), message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = group.name
            field.autocapitalizationType = .sentences
        }
        alert.addAction(UIAlertAction(title: String(localized: "Cancelar"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "Salvar"), style: .default) { [weak self] _ in
            let name = (alert.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.count >= 2 else { return }
            Task { @MainActor in
                do {
                    let updated = try await NativeAPIClient.updateGroup(id: group.id, name: name)
                    self?.group = updated
                    self?.title = updated.name
                    KCHaptics.success()
                } catch {
                    let err = UIAlertController(title: String(localized: "Erro"), message: error.localizedDescription, preferredStyle: .alert)
                    err.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
                    self?.present(err, animated: true)
                }
            }
        })
        present(alert, animated: true)
    }

    private func confirmDeleteGroup() {
        guard let group else { return }
        let alert = UIAlertController(
            title: String(localized: "Excluir «\(group.name)»?"),
            message: String(localized: "Esta ação remove o grupo e as publicações. Não dá para desfazer."),
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: String(localized: "Cancelar"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "Excluir grupo"), style: .destructive) { [weak self] _ in
            Task { @MainActor in
                do {
                    try await NativeAPIClient.deleteGroup(id: group.id)
                    self?.navigationController?.popViewController(animated: true)
                } catch {
                    let err = UIAlertController(title: String(localized: "Erro"), message: error.localizedDescription, preferredStyle: .alert)
                    err.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
                    self?.present(err, animated: true)
                }
            }
        })
        KCConfirmation.presentActionSheet(
            alert,
            from: self,
            barButtonItem: navigationItem.rightBarButtonItems?.last
        )
    }


    private func handleNotebookChip(_ id: String?) {
        guard let id, let filter = NoteFilter(rawValue: id) else {
            noteFilter = .all
            selectedTags.removeAll()
            selectedSpeakerIds.removeAll()
            filterChips.setSelected(NoteFilter.all.rawValue, animated: true)
            applyFilter()
            return
        }
        noteFilter = filter
        if filter == .all {
            // Easy clear: "Tudo" resets session tag + speaker filters.
            selectedTags.removeAll()
            selectedSpeakerIds.removeAll()
            applyFilter()
            return
        }
        if filter == .shared {
            // Real grants from `/notes/granted` — never invent from owned visibility.
            Task { @MainActor in
                if NativeAPIClient.hasBearer {
                    self.grantedNotes = (try? await NativeAPIClient.listGrantedNotes()) ?? self.grantedNotes
                }
                self.applyFilter()
            }
        } else if filter == .tags {
            presentTagPicker()
            applyFilter()
        } else if filter == .speakers {
            presentSpeakerFilter()
            applyFilter()
        } else {
            applyFilter()
        }
    }

    private func openGroupMembers() {
        guard let group else { return }
        let members = GroupMembersViewController(group: group)
        navigationController?.pushViewController(members, animated: true)
    }

    private func openInviteFriends() {
        guard let group, group.isAccepted else { return }
        let picker = GroupInviteFriendsViewController(group: group)
        navigationController?.pushViewController(picker, animated: true)
    }

    private func shareGroupInvite() {
        guard let group else { return }
        let url = NativeAPIClient.baseURL.appendingPathComponent("groups/\(group.id)")
        let text = String(format: String(localized: "Entre no grupo «%@» no Katecheo"), group.name)
        let vc = UIActivityViewController(activityItems: [text, url], applicationActivities: nil)
        KCConfirmation.presentActivity(
            vc,
            from: self,
            barButtonItem: navigationItem.rightBarButtonItems?.last
        )
    }

    /// Orador principal (`noteSpeakerId`) for the Caderno row speaker chip (TF194 #7).
    private func mainSpeakerName(for note: NativeAPIClient.NoteDocument?) -> String? {
        guard let note, let id = note.noteSpeakerId, !id.isEmpty else { return nil }
        if let name = speakers.first(where: { $0.id == id })?.name.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        let cached = LocalNoteCache.loadSpeakers().first(where: { $0.id == id })?.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let cached, !cached.isEmpty { return cached }
        return nil
    }

    private func presentTagPicker() {
        let tags = Array(Set(notes.flatMap(\.tags))).sorted()
        let items = tags.map { NotebookFilterMultiSelectSheet.Item(id: $0, title: "#\($0)") }
        let sheet = NotebookFilterMultiSelectSheet(
            title: String(localized: "Tags"),
            items: items,
            selected: selectedTags
        )
        sheet.onDone = { [weak self] next in
            self?.selectedTags = next
            self?.applyFilter()
        }
        KCSheetPresenter.present(sheet, from: self)
    }

    private func presentSpeakerFilter() {
        let items = speakers.map {
            NotebookFilterMultiSelectSheet.Item(id: $0.id, title: $0.name)
        }
        let sheet = NotebookFilterMultiSelectSheet(
            title: String(localized: "Speakers"),
            items: items,
            selected: selectedSpeakerIds
        )
        sheet.onDone = { [weak self] next in
            self?.selectedSpeakerIds = next
            self?.applyFilter()
        }
        KCSheetPresenter.present(sheet, from: self)
    }

    /// Button / selector entry — must not overload `showSignIn(auto:)` (Swift `#selector` ambiguity).
    @objc private func presentSignInTapped() {
        showSignIn(auto: false)
    }

    private var didAutoPresentSignIn = false

    private func showSignIn(auto: Bool) {
        if auto {
            if didAutoPresentSignIn { return }
            didAutoPresentSignIn = true
        }
        if presentedViewController is UINavigationController,
           (presentedViewController as? UINavigationController)?.viewControllers.first is NativeSignInViewController
        {
            return
        }
        let signIn = NativeSignInViewController()
        signIn.onSignedIn = { [weak self] in
            NotificationCenter.default.post(name: .nativeSessionDidChange, object: nil)
            self?.reload()
        }
        let nav = UINavigationController(rootViewController: signIn)
        KCChrome.style(navigationController: nav)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }
}
