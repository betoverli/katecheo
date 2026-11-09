import UIKit

/// Phase 3 native Perfil tab: identity, preferences, account (sign-out / delete).
final class ProfileViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    private enum Section: Int, CaseIterable {
        case preferences
        case account
        case guest
    }

    private enum PrefRow: Int, CaseIterable {
        case edit
        case friends
        case appearance
        case language
        case bible
        case notifications
        case help
    }

    private enum AccountRow: Int, CaseIterable {
        case signOut
        case exportData
        case deleteAccount
    }

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let refresh = UIRefreshControl()
    private var me: NativeAPIClient.MeDTO?
    private var loadError: String?
    private let headerStack = UIStackView()
    private let avatarView = UIImageView()
    private let nameLabel = UILabel()
    private let handleLabel = UILabel()
    private let emailLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        V2NChrome.styleScreen(view)
        title = String(localized: "Perfil")
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always
        if let nav = navigationController {
            V2NChrome.style(navigationController: nav)
        }

        tableView.translatesAutoresizingMaskIntoConstraints = false
        V2NChrome.styleGroupedTable(tableView)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        refresh.addTarget(self, action: #selector(reload), for: .valueChanged)
        tableView.refreshControl = refresh
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        buildHeader()
        applyGlassChromeIfAvailable()

        // Paint immediately from cache so the tab never flashes empty while networking.
        if NativeAPIClient.hasBearer, let cached = LocalSessionCache.loadMe() {
            me = cached
            updateHeader()
            tableView.reloadData()
            layoutHeader()
        } else {
            updateHeader()
        }

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
            if me == nil, NativeAPIClient.hasBearer, let cached = LocalSessionCache.loadMe() {
                me = cached
                updateHeader()
                tableView.reloadData()
                layoutHeader()
            }
            reload()
        }
    }

    private func buildHeader() {
        headerStack.axis = .vertical
        headerStack.alignment = .center
        headerStack.spacing = V2NDesign.Space.xs
        headerStack.isLayoutMarginsRelativeArrangement = true
        headerStack.layoutMargins = UIEdgeInsets(top: V2NDesign.Space.md, left: 20, bottom: V2NDesign.Space.xs, right: 20)

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.contentMode = .scaleAspectFill
        avatarView.clipsToBounds = true
        avatarView.layer.cornerRadius = 48
        avatarView.backgroundColor = V2NDesign.accentSoft
        avatarView.tintColor = V2NDesign.accent
        avatarView.layer.borderWidth = 2
        avatarView.layer.borderColor = V2NDesign.spine.withAlphaComponent(0.35).cgColor
        avatarView.isAccessibilityElement = true
        avatarView.accessibilityLabel = String(localized: "Foto do perfil")
        NSLayoutConstraint.activate([
            avatarView.widthAnchor.constraint(equalToConstant: 96),
            avatarView.heightAnchor.constraint(equalToConstant: 96),
        ])

        nameLabel.font = V2NDesign.screenTitle()
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 2
        nameLabel.adjustsFontForContentSizeCategory = true

        handleLabel.font = V2NDesign.rowSubtitle()
        handleLabel.textColor = .secondaryLabel
        handleLabel.textAlignment = .center
        handleLabel.adjustsFontForContentSizeCategory = true

        emailLabel.font = V2NDesign.caption()
        emailLabel.textColor = .tertiaryLabel
        emailLabel.textAlignment = .center
        emailLabel.numberOfLines = 2
        emailLabel.adjustsFontForContentSizeCategory = true

        headerStack.addArrangedSubview(avatarView)
        headerStack.addArrangedSubview(nameLabel)
        headerStack.addArrangedSubview(handleLabel)
        headerStack.addArrangedSubview(emailLabel)

        let container = UIView()
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(headerStack)
        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: container.topAnchor),
            headerStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            headerStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            headerStack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        // Autosize header after layout.
        container.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 200)
        tableView.tableHeaderView = container
    }

    private func layoutHeader() {
        guard let header = tableView.tableHeaderView else { return }
        header.setNeedsLayout()
        header.layoutIfNeeded()
        let height = headerStack.systemLayoutSizeFitting(
            CGSize(width: tableView.bounds.width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        var frame = header.frame
        frame.size.height = max(height, 120)
        frame.size.width = tableView.bounds.width
        header.frame = frame
        tableView.tableHeaderView = header
    }

    private func applyGlassChromeIfAvailable() {
        // Liquid Glass (iOS 26 SDK) paints system nav/tab chrome; older OS keeps classic UIKit.
        _ = V2NGlassMaterial.sdkHasLiquidGlass()
    }

    @objc private func reload() {
        Task { @MainActor in
            defer { refresh.endRefreshing() }
            guard NativeAPIClient.hasBearer else {
                me = nil
                loadError = nil
                LocalSessionCache.clearMe()
                updateHeader()
                tableView.reloadData()
                return
            }
            // Keep cached identity on screen while refreshing in the background.
            if me == nil, let cached = LocalSessionCache.loadMe() {
                me = cached
                updateHeader()
                tableView.reloadData()
            }
            do {
                let force = refresh.isRefreshing
                me = try await NativeAPIClient.getMe(force: force)
                LocalSessionCache.showOfflineHint = false
                loadError = nil
            } catch NativeAPIClient.APIError.unauthorized {
                // Only real auth failure clears session — never a transport error.
                me = nil
                LocalSessionCache.clearMe()
                loadError = String(localized: "Sessão expirada.")
            } catch {
                if me == nil, let cached = LocalSessionCache.loadMe() {
                    me = cached
                }
                LocalSessionCache.showOfflineHint = true
                loadError = me == nil ? error.localizedDescription : nil
            }
            updateHeader()
            tableView.reloadData()
            layoutHeader()
        }
    }

    private func updateHeader() {
        if let me {
            nameLabel.text = me.displayName.isEmpty ? String(localized: "Sem nome") : me.displayName
            let handle = me.prefs.handle
            var handleText = handle.isEmpty ? String(localized: "Defina um @usuário") : "@\(handle)"
            if LocalSessionCache.showOfflineHint {
                handleText += " · " + String(localized: "Offline")
            }
            handleLabel.text = handleText
            emailLabel.text = me.email ?? me.prefs.profileEmail
            tableView.tableHeaderView?.isHidden = false
            loadAvatar(urlString: me.prefs.avatarUrl)
        } else {
            nameLabel.text = String(localized: "Conta Katecheo")
            handleLabel.text = NativeAPIClient.hasBearer
                ? (loadError ?? String(localized: "Carregando…"))
                : String(localized: "Entre para ver seu perfil.")
            emailLabel.text = ""
            avatarView.image = UIImage(systemName: "person.crop.circle.fill")
            avatarView.contentMode = .scaleAspectFit
        }
        layoutHeader()
    }

    private func loadAvatar(urlString: String) {
        avatarView.contentMode = .scaleAspectFill
        guard let url = URL(string: urlString), !urlString.isEmpty else {
            avatarView.image = UIImage(systemName: "person.crop.circle.fill")
            avatarView.contentMode = .scaleAspectFit
            return
        }
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = UIImage(data: data) {
                    await MainActor.run { self.avatarView.image = image }
                }
            } catch {
                await MainActor.run {
                    self.avatarView.image = UIImage(systemName: "person.crop.circle.fill")
                    self.avatarView.contentMode = .scaleAspectFit
                }
            }
        }
    }

    /// Bearer (or cached me) means logged in — network errors must not look like logout.
    private var signedIn: Bool { me != nil || NativeAPIClient.hasBearer }

    private func sectionKind(at section: Int) -> Section {
        if !signedIn { return .guest }
        return section == 0 ? .preferences : .account
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        signedIn ? 2 : 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch sectionKind(at: section) {
        case .preferences: return PrefRow.allCases.count
        case .account: return AccountRow.allCases.count
        case .guest: return 1
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch sectionKind(at: section) {
        case .preferences: return String(localized: "Preferências")
        case .account: return String(localized: "Conta")
        case .guest: return nil
        }
    }

    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        guard let header = view as? UITableViewHeaderFooterView else { return }
        header.textLabel?.font = V2NDesign.sectionHeader()
        header.textLabel?.textColor = .secondaryLabel
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if sectionKind(at: section) == .guest, let loadError { return loadError }
        return nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .default
        cell.accessoryView = nil

        switch sectionKind(at: indexPath.section) {
        case .guest:
            config.text = String(localized: "Entrar")
            config.secondaryText = String(localized: "Google, Apple ou email")
            config.image = UIImage(systemName: "person.badge.key")
            cell.accessoryType = .none
        case .preferences:
            guard let row = PrefRow(rawValue: indexPath.row) else { break }
            switch row {
            case .edit:
                config.text = String(localized: "Editar perfil")
                config.secondaryText = me?.prefs.displayName
                config.image = UIImage(systemName: "pencil")
            case .friends:
                config.text = String(localized: "Amigos")
                let pending = V2NActivityStore.items(kind: .friendPending).count
                let accepted = V2NActivityStore.items(kind: .friendAccepted).count
                if pending + accepted > 0 {
                    config.secondaryText = String(localized: "Atividade nova")
                } else {
                    config.secondaryText = String(localized: "Pedidos e aceites")
                }
                config.image = UIImage(systemName: "person.2")
            case .appearance:
                config.text = String(localized: "Aparência")
                config.secondaryText = themeLabel(me?.prefs.theme ?? "system")
                config.image = UIImage(systemName: "circle.lefthalf.filled")
            case .language:
                config.text = String(localized: "Idioma")
                config.secondaryText = String(localized: "Segue o idioma do iPhone")
                config.image = UIImage(systemName: "globe")
            case .bible:
                config.text = String(localized: "App de Bíblia")
                config.secondaryText = bibleAppLabel(me?.prefs.appId ?? "youversion")
                config.image = UIImage(systemName: "book")
            case .notifications:
                config.text = String(localized: "Avisos")
                let devices = me?.notify.apnsDevices ?? 0
                config.secondaryText = devices > 0 ? String(localized: "\(devices) dispositivo(s)") : String(localized: "Configurar alertas")
                config.image = UIImage(systemName: "bell")
            case .help:
                config.text = String(localized: "Sobre e ajuda")
                config.secondaryText = String(localized: "Privacidade · site")
                config.image = UIImage(systemName: "questionmark.circle")
            }
        case .account:
            guard let row = AccountRow(rawValue: indexPath.row) else { break }
            cell.accessoryType = .none
            switch row {
            case .signOut:
                config.text = String(localized: "Sair da conta")
                config.textProperties.color = .label
                config.image = UIImage(systemName: "rectangle.portrait.and.arrow.right")
            case .exportData:
                config.text = String(localized: "Baixar meus dados")
                config.image = UIImage(systemName: "square.and.arrow.up")
            case .deleteAccount:
                config.text = String(localized: "Excluir conta")
                config.textProperties.color = .systemRed
                config.image = UIImage(systemName: "trash")
                config.imageProperties.tintColor = .systemRed
            }
        }

        cell.contentConfiguration = config
        cell.accessoryView = nil
        cell.v2nApplyThemedGroupedCell()
        if case .preferences = sectionKind(at: indexPath.section),
           PrefRow(rawValue: indexPath.row) == .friends,
           V2NActivityStore.friendsEntryDot
        {
            cell.accessibilityValue = String(localized: "Não lido")
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        V2NHaptics.selection()
        switch sectionKind(at: indexPath.section) {
        case .guest:
            presentSignIn()
        case .preferences:
            guard let row = PrefRow(rawValue: indexPath.row), let me else { return }
            switch row {
            case .edit:
                let edit = ProfileEditViewController(me: me) { [weak self] in self?.reload() }
                navigationController?.pushViewController(edit, animated: true)
            case .friends:
                navigationController?.pushViewController(FriendsActivityViewController(), animated: true)
            case .appearance:
                let vc = ProfileThemeViewController(theme: me.prefs.theme) { [weak self] in self?.reload() }
                navigationController?.pushViewController(vc, animated: true)
            case .language:
                let vc = ProfileLanguageViewController(prefs: me.prefs) { [weak self] in self?.reload() }
                navigationController?.pushViewController(vc, animated: true)
            case .bible:
                let vc = ProfileBibleViewController(prefs: me.prefs) { [weak self] in self?.reload() }
                navigationController?.pushViewController(vc, animated: true)
            case .notifications:
                let vc = ProfileNotifyViewController(notify: me.notify) { [weak self] in self?.reload() }
                navigationController?.pushViewController(vc, animated: true)
            case .help:
                openHelp()
            }
        case .account:
            guard let row = AccountRow(rawValue: indexPath.row) else { return }
            switch row {
            case .signOut: confirmSignOut()
            case .exportData: exportData()
            case .deleteAccount: confirmDeleteAccount()
            }
        }
    }

    private func presentSignIn() {
        let signIn = NativeSignInViewController()
        signIn.onSignedIn = { [weak self] in
            NotificationCenter.default.post(name: .nativeSessionDidChange, object: nil)
            self?.reload()
        }
        let nav = UINavigationController(rootViewController: signIn)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }

    private func confirmSignOut() {
        let alert = UIAlertController(
            title: String(localized: "Sair da conta?"),
            message: String(localized: "Você vai sair desta conta neste dispositivo."),
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: String(localized: "Cancelar"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "Sair da conta"), style: .destructive) { [weak self] _ in
            Task { @MainActor in
                await NativeLoginService.shared.signOut()
                NotificationCenter.default.post(name: .nativeSessionDidChange, object: nil)
                self?.me = nil
                self?.tableView.reloadData()
                self?.updateHeader()
                self?.presentSignIn()
            }
        })
        if let pop = alert.popoverPresentationController {
            pop.sourceView = tableView
            pop.sourceRect = tableView.bounds
        }
        present(alert, animated: true)
    }

    private func exportData() {
        Task { @MainActor in
            do {
                let data = try await NativeAPIClient.exportAccount()
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("katecheo-dados.json")
                try data.write(to: url, options: .atomic)
                let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                if let pop = activity.popoverPresentationController {
                    pop.sourceView = tableView
                    pop.sourceRect = tableView.bounds
                }
                present(activity, animated: true)
            } catch {
                presentError(error.localizedDescription)
            }
        }
    }

    private func confirmDeleteAccount() {
        let alert = UIAlertController(
            title: String(localized: "Excluir conta?"),
            message: String(localized: "Isso remove permanentemente suas notas, grupos e preferências. Não pode ser desfeito."),
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: String(localized: "Cancelar"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "Excluir conta"), style: .destructive) { [weak self] _ in
            self?.performDeleteAccount()
        })
        if let pop = alert.popoverPresentationController {
            pop.sourceView = tableView
            pop.sourceRect = tableView.bounds
        }
        present(alert, animated: true)
    }

    private func performDeleteAccount() {
        Task { @MainActor in
            do {
                try await NativeAPIClient.deleteAccount()
                await NativeLoginService.shared.signOut()
                NotificationCenter.default.post(name: .nativeSessionDidChange, object: nil)
                me = nil
                tableView.reloadData()
                updateHeader()
                let done = UIAlertController(
                    title: String(localized: "Conta apagada"),
                    message: String(localized: "Sua conta foi removida."),
                    preferredStyle: .alert
                )
                done.addAction(UIAlertAction(title: String(localized: "OK"), style: .default) { [weak self] _ in
                    self?.presentSignIn()
                })
                present(done, animated: true)
            } catch {
                presentError(error.localizedDescription)
            }
        }
    }

    private func openHelp() {
        let url = AppSite.aboutURL()
        UIApplication.shared.open(url)
    }

    private func presentError(_ message: String) {
        let alert = UIAlertController(title: String(localized: "Erro"), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
        present(alert, animated: true)
    }

    private func themeLabel(_ theme: String) -> String {
        switch theme {
        case "light": return String(localized: "Claro")
        case "dark": return String(localized: "Escuro")
        default: return String(localized: "Sistema")
        }
    }

    private func bibleAppLabel(_ appId: String) -> String {
        ProfileBibleCatalog.name(for: appId)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutHeader()
        v2nApplyTabBarScrollClearance(to: tableView)
    }
}
