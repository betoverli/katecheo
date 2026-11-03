import UIKit

/// Phase 1 native notebook list: search, swipe share/delete, compose.
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
    private let emptyLabel = UILabel()
    private let signInButton = UIButton(type: .system)
    private var statusBanner = UILabel()
    /// When set, this list shows notes published to the group (Phase 2).
    private var group: NativeAPIClient.GroupDTO?

    convenience init(group: NativeAPIClient.GroupDTO) {
        self.init(nibName: nil, bundle: nil)
        self.group = group
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = group?.name ?? "Caderno"
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always

        var trailing: [UIBarButtonItem] = [
            UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), style: .plain, target: self, action: #selector(moreMenu)),
        ]
        if group == nil || group?.canPost == true {
            trailing.insert(UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(composeNote)), at: 0)
        }
        navigationItem.rightBarButtonItems = trailing

        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = group == nil ? "Pesquisar notas" : "Pesquisar notas do grupo"
        navigationItem.searchController = search
        definesPresentationContext = true

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(SubtitleNoteCell.self, forCellReuseIdentifier: SubtitleNoteCell.reuseId)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
        refresh.addTarget(self, action: #selector(reload), for: .valueChanged)
        tableView.refreshControl = refresh
        view.addSubview(tableView)

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.textAlignment = .center
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.numberOfLines = 0
        emptyLabel.font = .preferredFont(forTextStyle: .body)
        emptyLabel.isHidden = true
        view.addSubview(emptyLabel)

        signInButton.translatesAutoresizingMaskIntoConstraints = false
        signInButton.setTitle("Entrar", for: .normal)
        signInButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        signInButton.addTarget(self, action: #selector(presentSignInTapped), for: .touchUpInside)
        signInButton.isHidden = true
        view.addSubview(signInButton)

        statusBanner.translatesAutoresizingMaskIntoConstraints = false
        statusBanner.font = .preferredFont(forTextStyle: .caption1)
        statusBanner.textColor = .secondaryLabel
        statusBanner.textAlignment = .center
        statusBanner.numberOfLines = 2
        view.addSubview(statusBanner)

        NSLayoutConstraint.activate([
            statusBanner.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            statusBanner.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            statusBanner.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),

            tableView.topAnchor.constraint(equalTo: statusBanner.bottomAnchor, constant: 4),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -24),
            emptyLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            emptyLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),

            signInButton.topAnchor.constraint(equalTo: emptyLabel.bottomAnchor, constant: 16),
            signInButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])

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
                    statusBanner.text = "Inicia sessão para ver as notas do grupo."
                    signInButton.isHidden = false
                    emptyLabel.text = "Entra para sincronizar este grupo."
                    emptyLabel.isHidden = false
                    return
                }
                notes = LocalNoteCache.loadNotes()
                applyFilter()
                statusBanner.text = notes.isEmpty ? "Inicia sessão para sincronizar o caderno." : "Offline / sem sessão — cache local."
                signInButton.isHidden = false
                emptyLabel.text = notes.isEmpty ? "Nenhuma nota ainda.\nEntra para ver o teu caderno." : nil
                emptyLabel.isHidden = !notes.isEmpty
                // Fresh install / no session: present native sign-in once.
                if notes.isEmpty, presentedViewController == nil {
                    showSignIn(auto: true)
                }
                return
            }
            signInButton.isHidden = true
            do {
                if let group {
                    let refreshed = try await NativeAPIClient.getGroup(id: group.id)
                    self.group = refreshed
                    title = refreshed.name
                    groupCards = try await NativeAPIClient.listGroupNotes(groupId: group.id)
                    notes = groupCards.compactMap { $0.document }
                    statusBanner.text = "\(groupCards.count) notas no grupo · sincronizado"
                    applyFilter()
                    return
                }
                async let remoteNotes = NativeAPIClient.listNotes()
                async let remoteSpeakers = NativeAPIClient.listSpeakers()
                notes = try await remoteNotes
                speakers = try await remoteSpeakers
                statusBanner.text = "\(notes.count) notas · sincronizado"
                applyFilter()
            } catch NativeAPIClient.APIError.unauthorized {
                statusBanner.text = "Sessão expirada."
                signInButton.isHidden = false
                if group == nil {
                    notes = LocalNoteCache.loadNotes()
                }
                applyFilter()
            } catch {
                if group == nil {
                    notes = LocalNoteCache.loadNotes()
                    statusBanner.text = "Sem rede — a mostrar cache. \(error.localizedDescription)"
                } else {
                    statusBanner.text = "Sem rede. \(error.localizedDescription)"
                }
                applyFilter()
            }
        }
    }

    private var isGroupMode: Bool { group != nil }

    private func applyFilter() {
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
            emptyLabel.text = filteredCards.isEmpty
                ? (q.isEmpty ? "Nenhuma nota neste grupo." : "Nenhum resultado.")
                : nil
            emptyLabel.isHidden = !filteredCards.isEmpty
            tableView.reloadData()
            return
        }
        if q.isEmpty {
            filtered = notes
        } else {
            filtered = notes.filter { note in
                if note.title.lowercased().contains(q) { return true }
                if note.tags.contains(where: { $0.lowercased().contains(q) }) { return true }
                if note.happenedAt.contains(q) { return true }
                if note.preview.lowercased().contains(q) { return true }
                return false
            }
        }
        if filtered.isEmpty {
            if !NativeAPIClient.hasBearer && notes.isEmpty {
                emptyLabel.text = "Nenhuma nota ainda.\nEntra para ver o teu caderno."
                emptyLabel.isHidden = false
            } else if NativeAPIClient.hasBearer || !notes.isEmpty {
                emptyLabel.text = q.isEmpty ? "Nenhuma nota ainda." : "Nenhum resultado."
                emptyLabel.isHidden = false
            }
        } else {
            emptyLabel.isHidden = true
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
        let cell = tableView.dequeueReusableCell(withIdentifier: SubtitleNoteCell.reuseId, for: indexPath) as! SubtitleNoteCell
        if isGroupMode {
            let card = filteredCards[indexPath.row]
            let title = card.note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Reunião" : card.note.title
            let preview = card.document?.preview ?? card.author.displayName
            cell.configure(title: title, subtitle: "\(card.note.happenedAt) · \(preview)", tags: card.document?.tags ?? [])
            return cell
        }
        let note = filtered[indexPath.row]
        let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Reunião" : note.title
        cell.configure(title: title, subtitle: "\(note.happenedAt) · \(note.preview)", tags: note.tags)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if isGroupMode {
            let card = filteredCards[indexPath.row]
            guard card.owned, let doc = card.document else {
                let alert = UIAlertController(
                    title: card.note.title.isEmpty ? "Reunião" : card.note.title,
                    message: "Nota de \(card.author.displayName). Só o autor a pode editar neste ecrã nativo.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
                return
            }
            let detail = NoteDetailViewController(noteId: doc.id, initial: doc)
            navigationController?.pushViewController(detail, animated: true)
            return
        }
        let note = filtered[indexPath.row]
        let detail = NoteDetailViewController(noteId: note.id, initial: note)
        navigationController?.pushViewController(detail, animated: true)
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        if isGroupMode {
            let card = filteredCards[indexPath.row]
            guard card.owned || group?.isAdmin == true else { return nil }
            let remove = UIContextualAction(style: .destructive, title: "Retirar") { [weak self] _, _, done in
                self?.confirmUnpublish(card) { done($0) }
            }
            remove.image = UIImage(systemName: "folder.badge.minus")
            return UISwipeActionsConfiguration(actions: [remove])
        }
        let note = filtered[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "Apagar") { [weak self] _, _, done in
            self?.confirmDelete(note) { done($0) }
        }
        delete.image = UIImage(systemName: "trash")
        return UISwipeActionsConfiguration(actions: [delete])
    }

    func tableView(
        _ tableView: UITableView,
        leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        if isGroupMode {
            guard let doc = filteredCards[indexPath.row].document else { return nil }
            let share = UIContextualAction(style: .normal, title: "Compartilhar") { [weak self] _, view, done in
                self?.share(doc, from: view)
                done(true)
            }
            share.image = UIImage(systemName: "square.and.arrow.up")
            share.backgroundColor = .systemBlue
            return UISwipeActionsConfiguration(actions: [share])
        }
        let note = filtered[indexPath.row]
        let share = UIContextualAction(style: .normal, title: "Compartilhar") { [weak self] _, view, done in
            self?.share(note, from: view)
            done(true)
        }
        share.image = UIImage(systemName: "square.and.arrow.up")
        share.backgroundColor = .systemBlue
        return UISwipeActionsConfiguration(actions: [share])
    }

    private func confirmUnpublish(_ card: NativeAPIClient.GroupNoteCardDTO, completion: @escaping (Bool) -> Void) {
        guard let group else {
            completion(false)
            return
        }
        let alert = UIAlertController(title: nil, message: "Retirar esta nota do grupo?", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { _ in completion(false) })
        alert.addAction(UIAlertAction(title: "Retirar do grupo", style: .destructive) { [weak self] _ in
            Task { @MainActor in
                do {
                    try await NativeAPIClient.unpublishNote(noteId: card.note.id, fromGroupId: group.id)
                    self?.groupCards.removeAll { $0.note.id == card.note.id }
                    self?.applyFilter()
                    completion(true)
                } catch {
                    completion(false)
                    let err = UIAlertController(title: "Erro", message: error.localizedDescription, preferredStyle: .alert)
                    err.addAction(UIAlertAction(title: "OK", style: .default))
                    self?.present(err, animated: true)
                }
            }
        })
        if let pop = alert.popoverPresentationController {
            pop.sourceView = tableView
            pop.sourceRect = tableView.bounds
        }
        present(alert, animated: true)
    }

    private func confirmDelete(_ note: NativeAPIClient.NoteDocument, completion: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: "Apagar esta nota?", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { _ in completion(false) })
        alert.addAction(UIAlertAction(title: "Apagar nota", style: .destructive) { [weak self] _ in
            Task { @MainActor in
                do {
                    if NativeAPIClient.hasBearer {
                        try await NativeAPIClient.deleteNote(id: note.id)
                    } else {
                        LocalNoteCache.removeNote(id: note.id)
                    }
                    self?.notes.removeAll { $0.id == note.id }
                    self?.applyFilter()
                    completion(true)
                } catch {
                    completion(false)
                    let err = UIAlertController(title: "Erro", message: error.localizedDescription, preferredStyle: .alert)
                    err.addAction(UIAlertAction(title: "OK", style: .default))
                    self?.present(err, animated: true)
                }
            }
        })
        if let pop = alert.popoverPresentationController {
            pop.sourceView = tableView
            pop.sourceRect = tableView.bounds
        }
        present(alert, animated: true)
    }

    private func share(_ note: NativeAPIClient.NoteDocument, from source: UIView) {
        let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Reunião" : note.title
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
                let err = UIAlertController(title: "Não foi possível criar", message: error.localizedDescription, preferredStyle: .alert)
                err.addAction(UIAlertAction(title: "OK", style: .default))
                present(err, animated: true)
            }
        }
    }

    @objc private func moreMenu() {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Atualizar", style: .default) { [weak self] _ in self?.reload() })
        if let group, group.isAdmin {
            sheet.addAction(UIAlertAction(title: "Renomear grupo…", style: .default) { [weak self] _ in
                self?.promptRenameGroup()
            })
            sheet.addAction(UIAlertAction(title: "Apagar grupo…", style: .destructive) { [weak self] _ in
                self?.confirmDeleteGroup()
            })
        }
        if !isGroupMode {
            sheet.addAction(UIAlertAction(title: "Speakers…", style: .default) { [weak self] _ in
                let picker = SpeakerPickerViewController(mode: .manage, onManaged: { [weak self] in
                    self?.reload()
                })
                let nav = UINavigationController(rootViewController: picker)
                self?.present(nav, animated: true)
            })
            if NativeAPIClient.hasBearer {
                sheet.addAction(UIAlertAction(title: "Terminar sessão", style: .destructive) { [weak self] _ in
                    Task { @MainActor in
                        await NativeLoginService.shared.signOut()
                        self?.notes = LocalNoteCache.loadNotes()
                        self?.applyFilter()
                        self?.showSignIn(auto: false)
                    }
                })
            } else {
                sheet.addAction(UIAlertAction(title: "Entrar", style: .default) { [weak self] _ in
                    self?.showSignIn(auto: false)
                })
            }
        }
        sheet.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.barButtonItem = navigationItem.rightBarButtonItems?.last
        }
        present(sheet, animated: true)
    }

    private func promptRenameGroup() {
        guard let group else { return }
        let alert = UIAlertController(title: "Renomear grupo", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = group.name
            field.autocapitalizationType = .sentences
        }
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
        alert.addAction(UIAlertAction(title: "Guardar", style: .default) { [weak self] _ in
            let name = (alert.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.count >= 2 else { return }
            Task { @MainActor in
                do {
                    let updated = try await NativeAPIClient.updateGroup(id: group.id, name: name)
                    self?.group = updated
                    self?.title = updated.name
                } catch {
                    let err = UIAlertController(title: "Erro", message: error.localizedDescription, preferredStyle: .alert)
                    err.addAction(UIAlertAction(title: "OK", style: .default))
                    self?.present(err, animated: true)
                }
            }
        })
        present(alert, animated: true)
    }

    private func confirmDeleteGroup() {
        guard let group else { return }
        let alert = UIAlertController(
            title: "Apagar «\(group.name)»?",
            message: "Esta ação remove o grupo e as publicações. Não se pode desfazer.",
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
        alert.addAction(UIAlertAction(title: "Apagar grupo", style: .destructive) { [weak self] _ in
            Task { @MainActor in
                do {
                    try await NativeAPIClient.deleteGroup(id: group.id)
                    self?.navigationController?.popViewController(animated: true)
                } catch {
                    let err = UIAlertController(title: "Erro", message: error.localizedDescription, preferredStyle: .alert)
                    err.addAction(UIAlertAction(title: "OK", style: .default))
                    self?.present(err, animated: true)
                }
            }
        })
        if let pop = alert.popoverPresentationController {
            pop.barButtonItem = navigationItem.rightBarButtonItems?.last
        }
        present(alert, animated: true)
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
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }
}

private final class SubtitleNoteCell: UITableViewCell {
    static let reuseId = "SubtitleNoteCell"

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)
        textLabel?.numberOfLines = 1
        detailTextLabel?.numberOfLines = 2
        detailTextLabel?.textColor = .secondaryLabel
        accessoryType = .disclosureIndicator
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, subtitle: String, tags: [String]) {
        textLabel?.text = title
        let tagSuffix = tags.isEmpty ? "" : "  ·  " + tags.map { "#\($0)" }.joined(separator: " ")
        detailTextLabel?.text = subtitle + tagSuffix
    }
}
