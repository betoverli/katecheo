import UIKit

/// Phase 1 native notebook list: search, icon-only swipe share/delete, compose.
/// Phase 2 also reuses this screen for a group's notes (`group` scope).
final class NotebookListViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, UISearchResultsUpdating {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let refresh = UIRefreshControl()
    private var notes: [NativeAPIClient.NoteDocument] = []
    private var filtered: [NativeAPIClient.NoteDocument] = []
    private var groupCards: [NativeAPIClient.GroupNoteCardDTO] = []
    private var filteredCards: [NativeAPIClient.GroupNoteCardDTO] = []
    private var speakers: [NativeAPIClient.SpeakerDTO] = []
    private let search = UISearchController(searchResultsController: nil)
    private let emptyState = V2NEmptyStateView()
    private let statusBanner = V2NStatusBanner()
    private let filterChips = V2NFilterChipsView()
    private enum NoteFilter: String { case all, tags, speakers, shared }
    private var noteFilter: NoteFilter = .all
    private var selectedTag: String?
    private var selectedSpeakerId: String?
    private var grantedNotes: [NativeAPIClient.NoteDocument] = []
    /// When set, this list shows notes published to the group (Phase 2).
    private var group: NativeAPIClient.GroupDTO?

    convenience init(group: NativeAPIClient.GroupDTO) {
        self.init(nibName: nil, bundle: nil)
        self.group = group
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        V2NChrome.styleScreen(view)
        title = group?.name ?? String(localized: "Caderno")
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always
        if let nav = navigationController {
            V2NChrome.style(navigationController: nav)
        }

        var trailing: [UIBarButtonItem] = [
            UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), style: .plain, target: self, action: #selector(moreMenu)),
        ]
        if group == nil || group?.canPost == true {
            trailing.insert(UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(composeNote)), at: 0)
        }
        navigationItem.rightBarButtonItems = trailing
        navigationItem.rightBarButtonItems?.first?.accessibilityLabel = String(localized: "Nova nota")
        navigationItem.rightBarButtonItems?.last?.accessibilityLabel = String(localized: "Mais opções")

        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = group == nil ? String(localized: "Pesquisar notas") : String(localized: "Pesquisar notas do grupo")
        navigationItem.searchController = search
        // Standard iOS: search collapses while scrolling the list; pull down reveals it.
        navigationItem.hidesSearchBarWhenScrolling = true
        definesPresentationContext = true

        tableView.translatesAutoresizingMaskIntoConstraints = false
        V2NChrome.styleGroupedTable(tableView)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(V2NNoteRowCell.self, forCellReuseIdentifier: V2NNoteRowCell.reuseId)
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
                    V2NFilterChip(id: NoteFilter.all.rawValue, title: String(localized: "Tudo"), systemImage: "square.stack"),
                    V2NFilterChip(id: NoteFilter.tags.rawValue, title: String(localized: "Tags"), systemImage: "number"),
                    V2NFilterChip(id: NoteFilter.speakers.rawValue, title: String(localized: "Speakers"), systemImage: "person.wave.2"),
                    V2NFilterChip(id: NoteFilter.shared.rawValue, title: String(localized: "Compartilhadas"), systemImage: "person.2"),
                ],
                selectedId: NoteFilter.all.rawValue
            )
            filterChips.onSelect = { [weak self] id in
                self?.handleNotebookChip(id)
            }
            view.addSubview(filterChips)
            NSLayoutConstraint.activate([
                filterChips.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: V2NDesign.Space.xxs),
                filterChips.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                filterChips.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ])
            tableTop = filterChips.bottomAnchor
            emptyTop = filterChips.bottomAnchor
        }

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: tableTop, constant: group == nil ? V2NDesign.Space.xxs : 0),
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
            name: V2NActivityStore.didChangeNotification,
            object: nil
        )
    }

    @objc private func refreshSharedChipDot() {
        filterChips.setBadgedIds(V2NActivityStore.sharedChipDot ? [NoteFilter.shared.rawValue] : [])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task { @MainActor in
            if !NativeAPIClient.hasBearer {
                _ = await NativeSessionBootstrap.migrateCookieToKeychainIfNeeded()
            }
            reload()
        }
    }

    @objc private func reload() {
        Task { @MainActor in
            defer { refresh.endRefreshing() }
            guard NativeAPIClient.hasBearer else {
                if group != nil {
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
                notes = LocalNoteCache.loadNotes()
                applyFilter()
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
                if notes.isEmpty, presentedViewController == nil {
                    showSignIn(auto: true)
                }
                return
            }
            do {
                if let group {
                    let refreshed = try await NativeAPIClient.getGroup(id: group.id)
                    self.group = refreshed
                    title = refreshed.name
                    groupCards = try await NativeAPIClient.listGroupNotes(groupId: group.id)
                    notes = groupCards.compactMap { $0.document }
                    // No persistent sync success banner — list content is enough.
                    setBannerStatus(nil)
                    applyFilter()
                    return
                }
                async let remoteNotes = NativeAPIClient.listNotes()
                async let remoteSpeakers = NativeAPIClient.listSpeakers()
                async let remoteGranted = NativeAPIClient.listGrantedNotes()
                notes = try await remoteNotes
                speakers = try await remoteSpeakers
                grantedNotes = (try? await remoteGranted) ?? []
                setBannerStatus(nil)
                applyFilter()
                Task { await V2NActivitySync.refreshFromServer() }
            } catch NativeAPIClient.APIError.unauthorized {
                setBannerStatus(String(localized: "Sessão expirada. Entre novamente."), kind: .error)
                if group == nil {
                    notes = LocalNoteCache.loadNotes()
                }
                applyFilter()
                showEmpty(
                    symbol: "exclamationmark.shield",
                    title: String(localized: "Sessão expirada"),
                    message: String(localized: "Entre de novo para continuar sincronizando."),
                    actionTitle: String(localized: "Entrar")
                )
                showSignIn(auto: true)
            } catch {
                if group == nil {
                    notes = LocalNoteCache.loadNotes()
                    let pending = NativeOutbox.pendingCount
                    if pending > 0 {
                        setBannerStatus(
                            String(localized: "Sem rede — mostrando cache · \(pending) pendente(s)."),
                            kind: .warning
                        )
                    } else {
                        setBannerStatus(String(localized: "Sem rede — mostrando cache."), kind: .warning)
                    }
                } else {
                    setBannerStatus(String(localized: "Sem rede. \(error.localizedDescription)"), kind: .error)
                }
                applyFilter()
            }
        }
    }

    private var isGroupMode: Bool { group != nil }

    /// Status banner stays in the table header; Caderno chips are pinned above the table.
    private func installTableHeader() {
        let width = max(view.bounds.width, UIScreen.main.bounds.width)
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
            statusBanner.topAnchor.constraint(equalTo: header.topAnchor, constant: hasText ? V2NDesign.Space.xxs : 0),
            statusBanner.leadingAnchor.constraint(equalTo: header.layoutMarginsGuide.leadingAnchor),
            statusBanner.trailingAnchor.constraint(equalTo: header.layoutMarginsGuide.trailingAnchor),
            bannerHeight,
            statusBanner.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: hasText ? -V2NDesign.Space.xxs : 0),
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

    private func setBannerStatus(_ text: String?, kind: V2NStatusBanner.Kind = .neutral) {
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
        var badged = Set<String>()
        if V2NActivityStore.sharedChipDot {
            badged.insert(NoteFilter.shared.rawValue)
        }
        filterChips.setBadgedIds(badged)
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
                if q.isEmpty {
                    showEmpty(
                        symbol: "tray",
                        title: String(localized: "Nenhuma nota neste grupo"),
                        message: String(localized: "Publique uma nota ou peça para alguém compartilhar.")
                    )
                } else {
                    showEmpty(symbol: "magnifyingglass", title: String(localized: "Nenhum resultado"), message: String(localized: "Tente outro termo de busca."))
                }
            } else {
                hideEmpty()
            }
            tableView.reloadData()
            return
        }
        var source = notes
        switch noteFilter {
        case .all:
            break
        case .tags:
            if let selectedTag {
                source = source.filter { $0.tags.contains(selectedTag) }
            } else {
                // Show notes that have any tag when filter is Tags without a secondary pick.
                source = source.filter { !$0.tags.isEmpty }
            }
        case .speakers:
            if let selectedSpeakerId {
                source = source.filter { noteIncludesSpeaker($0, speakerId: selectedSpeakerId) }
            } else {
                source = source.filter { noteIncludesSpeaker($0, speakerId: nil) }
            }
        case .shared:
            source = grantedNotes
        }
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
    }

    func updateSearchResults(for searchController: UISearchController) {
        applyFilter()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        isGroupMode ? filteredCards.count : filtered.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: V2NNoteRowCell.reuseId, for: indexPath) as! V2NNoteRowCell
        if isGroupMode {
            let card = filteredCards[indexPath.row]
            let title = card.note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "Reunião") : card.note.title
            let preview = card.document?.preview ?? card.author.displayName
            let day = AppLocale.displayDay(card.note.happenedAt)
            let speakerName = mainSpeakerName(for: card.document)
            let subtitle = [day, preview].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            cell.configure(title: title, subtitle: subtitle, tags: card.document?.tags ?? [], speakerName: speakerName)
            return cell
        }
        let note = filtered[indexPath.row]
        let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "Reunião") : note.title
        let day = AppLocale.displayDay(note.happenedAt)
        let speakerName = mainSpeakerName(for: note)
        let subtitle = [day, note.preview].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        cell.configure(title: title, subtitle: subtitle, tags: note.tags, speakerName: speakerName)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        V2NHaptics.selection()
        if isGroupMode {
            let card = filteredCards[indexPath.row]
            guard card.owned, let doc = card.document else {
                let alert = UIAlertController(
                    title: card.note.title.isEmpty ? String(localized: "Reunião") : card.note.title,
                    message: String(localized: "Nota de \(card.author.displayName). Só o autor pode editar nesta tela nativa."),
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
                present(alert, animated: true)
                return
            }
            let detail = NoteDetailViewController(noteId: doc.id, initial: doc)
            navigationController?.pushViewController(detail, animated: true)
            return
        }
        let note = filtered[indexPath.row]
        let isGranted = noteFilter == .shared || grantedNotes.contains(where: { $0.id == note.id })
        if isGranted {
            V2NActivityStore.markSharedNoteOpened(note.id)
        }
        let detail = NoteDetailViewController(noteId: note.id, initial: note, grantedReadOnly: isGranted)
        navigationController?.pushViewController(detail, animated: true)
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        if isGroupMode {
            let card = filteredCards[indexPath.row]
            guard card.owned || group?.isAdmin == true else { return nil }
            let remove = UIContextualAction.v2nIconOnly(
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
        let delete = UIContextualAction.v2nIconOnly(
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
        leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        if isGroupMode {
            guard let doc = filteredCards[indexPath.row].document else { return nil }
            let share = UIContextualAction.v2nIconOnly(
                style: .normal,
                systemName: "square.and.arrow.up",
                accessibilityLabel: String(localized: "Compartilhar"),
                backgroundColor: V2NDesign.bookmark
            ) { [weak self] _, view, done in
                self?.share(doc, from: view)
                done(true)
            }
            return UISwipeActionsConfiguration(actions: [share])
        }
        let note = filtered[indexPath.row]
        let share = UIContextualAction.v2nIconOnly(
            style: .normal,
            systemName: "square.and.arrow.up",
            accessibilityLabel: String(localized: "Compartilhar"),
            backgroundColor: V2NDesign.bookmark
        ) { [weak self] _, view, done in
            self?.share(note, from: view)
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [share])
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
                    V2NHaptics.success()
                    completion(true)
                } catch {
                    completion(false)
                    let err = UIAlertController(title: String(localized: "Erro"), message: error.localizedDescription, preferredStyle: .alert)
                    err.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
                    self?.present(err, animated: true)
                }
            }
        })
        anchorActionSheet(alert, from: source, at: indexPath)
        present(alert, animated: true)
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
                    if NativeAPIClient.hasBearer {
                        try await NativeAPIClient.deleteNote(id: note.id)
                    } else {
                        LocalNoteCache.removeNote(id: note.id)
                        NativeOutbox.enqueueNoteDelete(id: note.id)
                    }
                    self?.notes.removeAll { $0.id == note.id }
                    self?.applyFilter()
                    V2NHaptics.medium()
                    completion(true)
                } catch {
                    LocalNoteCache.removeNote(id: note.id)
                    NativeOutbox.enqueueNoteDelete(id: note.id)
                    self?.notes.removeAll { $0.id == note.id }
                    self?.applyFilter()
                    completion(true)
                }
            }
        })
        anchorActionSheet(alert, from: source, at: indexPath)
        present(alert, animated: true)
    }

    /// iPhone: standard action sheet. iPad: popover anchored to the swiped row/action.
    private func anchorActionSheet(_ alert: UIAlertController, from source: UIView?, at indexPath: IndexPath) {
        guard let pop = alert.popoverPresentationController else { return }
        if let source {
            pop.sourceView = source
            pop.sourceRect = source.bounds
        } else {
            pop.sourceView = tableView
            pop.sourceRect = tableView.rectForRow(at: indexPath)
        }
        pop.permittedArrowDirections = [.up, .down]
    }

    private func share(_ note: NativeAPIClient.NoteDocument, from source: UIView) {
        let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "Reunião") : note.title
        let text = note.preview
        let url = NativeAPIClient.baseURL.appendingPathComponent("n/\(note.id)")
        let vc = UIActivityViewController(activityItems: [title, text, url], applicationActivities: nil)
        if let pop = vc.popoverPresentationController {
            pop.sourceView = source
            pop.sourceRect = source.bounds
        }
        present(vc, animated: true)
    }

    @objc private func composeNote() {
        V2NHaptics.light()
        Task { @MainActor in
            guard NativeAPIClient.hasBearer else {
                showSignIn(auto: false)
                return
            }
            do {
                let created = try await NativeAPIClient.upsertNote(NativeAPIClient.emptyNote())
                if let group {
                    try await NativeAPIClient.publishNote(noteId: created.id, toGroupId: group.id)
                    reload()
                } else {
                    notes.insert(created, at: 0)
                    applyFilter()
                }
                let detail = NoteDetailViewController(noteId: created.id, initial: created)
                navigationController?.pushViewController(detail, animated: true)
            } catch {
                let err = UIAlertController(title: String(localized: "Não foi possível criar"), message: error.localizedDescription, preferredStyle: .alert)
                err.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
                present(err, animated: true)
            }
        }
    }

    @objc private func moreMenu() {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: String(localized: "Atualizar"), style: .default) { [weak self] _ in self?.reload() })
        if let group, group.isAccepted {
            sheet.addAction(UIAlertAction(title: String(localized: "Membros"), style: .default) { [weak self] _ in
                self?.openGroupMembers()
            })
            sheet.addAction(UIAlertAction(title: String(localized: "Convidar…"), style: .default) { [weak self] _ in
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
        if let pop = sheet.popoverPresentationController {
            pop.barButtonItem = navigationItem.rightBarButtonItems?.last
        }
        present(sheet, animated: true)
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
                    V2NHaptics.success()
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
        if let pop = alert.popoverPresentationController {
            pop.barButtonItem = navigationItem.rightBarButtonItems?.last
        }
        present(alert, animated: true)
    }


    private func handleNotebookChip(_ id: String?) {
        guard let id, let filter = NoteFilter(rawValue: id) else {
            noteFilter = .all
            selectedTag = nil
            selectedSpeakerId = nil
            filterChips.setSelected(NoteFilter.all.rawValue, animated: true)
            applyFilter()
            return
        }
        noteFilter = filter
        selectedTag = nil
        selectedSpeakerId = nil
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

    private func shareGroupInvite() {
        guard let group else { return }
        let url = NativeAPIClient.baseURL.appendingPathComponent("groups/\(group.id)")
        let text = String(format: String(localized: "Entre no grupo «%@» no Verse2Note"), group.name)
        let vc = UIActivityViewController(activityItems: [text, url], applicationActivities: nil)
        if let pop = vc.popoverPresentationController {
            pop.barButtonItem = navigationItem.rightBarButtonItems?.last
        }
        present(vc, animated: true)
    }

    private func noteIncludesSpeaker(_ note: NativeAPIClient.NoteDocument, speakerId: String?) -> Bool {
        if let speakerId {
            if note.noteSpeakerId == speakerId { return true }
            return note.body.blocks.contains { block in
                if block.type == "speakerSection", block.speakerId == speakerId { return true }
                return false
            }
        }
        if note.noteSpeakerId != nil { return true }
        return note.body.blocks.contains { $0.type == "speakerSection" }
    }

    /// Orador principal (`noteSpeakerId`) for the Caderno row subtitle (TF194 #7).
    private func mainSpeakerName(for note: NativeAPIClient.NoteDocument?) -> String? {
        guard let note, let id = note.noteSpeakerId, !id.isEmpty else { return nil }
        if let name = speakers.first(where: { $0.id == id })?.name, !name.isEmpty {
            return name
        }
        return LocalNoteCache.loadSpeakers().first(where: { $0.id == id })?.name
    }

    private func presentTagPicker() {
        let tags = Array(Set(notes.flatMap(\.tags))).sorted()
        guard !tags.isEmpty else {
            applyFilter()
            return
        }
        let sheet = UIAlertController(title: String(localized: "Tags"), message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: String(localized: "Todas as tags"), style: .default) { [weak self] _ in
            self?.selectedTag = nil
            self?.applyFilter()
        })
        for tag in tags.prefix(20) {
            sheet.addAction(UIAlertAction(title: "#\(tag)", style: .default) { [weak self] _ in
                self?.selectedTag = tag
                self?.applyFilter()
            })
        }
        sheet.addAction(UIAlertAction(title: String(localized: "Cancelar"), style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = filterChips
        }
        present(sheet, animated: true)
    }

    private func presentSpeakerFilter() {
        guard !speakers.isEmpty else {
            applyFilter()
            return
        }
        let sheet = UIAlertController(title: String(localized: "Speakers"), message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: String(localized: "Todos os speakers"), style: .default) { [weak self] _ in
            self?.selectedSpeakerId = nil
            self?.applyFilter()
        })
        for speaker in speakers.prefix(20) {
            sheet.addAction(UIAlertAction(title: speaker.name, style: .default) { [weak self] _ in
                self?.selectedSpeakerId = speaker.id
                self?.applyFilter()
            })
        }
        sheet.addAction(UIAlertAction(title: String(localized: "Cancelar"), style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = filterChips
        }
        present(sheet, animated: true)
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
        V2NChrome.style(navigationController: nav)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }
}
