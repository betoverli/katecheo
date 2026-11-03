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
        view.backgroundColor = .systemBackground
        title = "Perfil"
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always

        tableView.translatesAutoresizingMaskIntoConstraints = false
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

    private func buildHeader() {
        headerStack.axis = .vertical
        headerStack.alignment = .center
        headerStack.spacing = 8
        headerStack.isLayoutMarginsRelativeArrangement = true
        headerStack.layoutMargins = UIEdgeInsets(top: 16, left: 20, bottom: 8, right: 20)

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.contentMode = .scaleAspectFill
        avatarView.clipsToBounds = true
        avatarView.layer.cornerRadius = 48
        avatarView.backgroundColor = .secondarySystemFill
        avatarView.tintColor = .secondaryLabel
        NSLayoutConstraint.activate([
            avatarView.widthAnchor.constraint(equalToConstant: 96),
            avatarView.heightAnchor.constraint(equalToConstant: 96),
        ])

        nameLabel.font = .preferredFont(forTextStyle: .title2)
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 2

        handleLabel.font = .preferredFont(forTextStyle: .subheadline)
        handleLabel.textColor = .secondaryLabel
        handleLabel.textAlignment = .center

        emailLabel.font = .preferredFont(forTextStyle: .footnote)
        emailLabel.textColor = .tertiaryLabel
        emailLabel.textAlignment = .center
        emailLabel.numberOfLines = 2

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
                updateHeader()
                tableView.reloadData()
                return
            }
            do {
                me = try await NativeAPIClient.getMe()
                loadError = nil
            } catch NativeAPIClient.APIError.unauthorized {
                me = nil
                loadError = "Sessão expirada."
            } catch {
                loadError = error.localizedDescription
            }
            updateHeader()
            tableView.reloadData()
            layoutHeader()
        }
    }

    private func updateHeader() {
        if let me {
            nameLabel.text = me.displayName.isEmpty ? "Sem nome" : me.displayName
            let handle = me.prefs.handle
            handleLabel.text = handle.isEmpty ? "Defina um @usuário" : "@\(handle)"
            emailLabel.text = me.email ?? me.prefs.profileEmail
            tableView.tableHeaderView?.isHidden = false
            loadAvatar(urlString: me.prefs.avatarUrl)
        } else {
            nameLabel.text = "Conta Verse2Note"
            handleLabel.text = NativeAPIClient.hasBearer ? (loadError ?? "Carregando…") : "Entre para ver seu perfil."
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

    private var signedIn: Bool { me != nil }

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
        case .preferences: return "Preferências"
        case .account: return "Conta"
        case .guest: return nil
        }
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
            config.text = "Entrar"
            config.secondaryText = "Google, Apple ou email"
            config.image = UIImage(systemName: "person.badge.key")
            cell.accessoryType = .none
        case .preferences:
            guard let row = PrefRow(rawValue: indexPath.row) else { break }
            switch row {
            case .edit:
                config.text = "Editar perfil"
                config.secondaryText = me?.prefs.displayName
                config.image = UIImage(systemName: "pencil")
            case .appearance:
                config.text = "Aparência"
                config.secondaryText = themeLabel(me?.prefs.theme ?? "system")
                config.image = UIImage(systemName: "circle.lefthalf.filled")
            case .language:
                config.text = "Idioma"
                config.secondaryText = languageLabel(me?.prefs.locale ?? "pt")
                config.image = UIImage(systemName: "globe")
            case .bible:
                config.text = "App de Bíblia"
                config.secondaryText = bibleAppLabel(me?.prefs.appId ?? "youversion")
                config.image = UIImage(systemName: "book")
            case .notifications:
                config.text = "Avisos"
                let devices = me?.notify.apnsDevices ?? 0
                config.secondaryText = devices > 0 ? "\(devices) dispositivo(s)" : "Configurar alertas"
                config.image = UIImage(systemName: "bell")
            case .help:
                config.text = "Sobre e ajuda"
                config.secondaryText = "Privacidade · site"
                config.image = UIImage(systemName: "questionmark.circle")
            }
        case .account:
            guard let row = AccountRow(rawValue: indexPath.row) else { break }
            cell.accessoryType = .none
            switch row {
            case .signOut:
                config.text = "Sair da conta"
                config.textProperties.color = .label
                config.image = UIImage(systemName: "rectangle.portrait.and.arrow.right")
            case .exportData:
                config.text = "Baixar meus dados"
                config.image = UIImage(systemName: "square.and.arrow.up")
            case .deleteAccount:
                config.text = "Excluir conta"
                config.textProperties.color = .systemRed
                config.image = UIImage(systemName: "trash")
                config.imageProperties.tintColor = .systemRed
            }
        }

        cell.contentConfiguration = config
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch sectionKind(at: indexPath.section) {
        case .guest:
            presentSignIn()
        case .preferences:
            guard let row = PrefRow(rawValue: indexPath.row), let me else { return }
            switch row {
            case .edit:
                let edit = ProfileEditViewController(me: me) { [weak self] in self?.reload() }
                navigationController?.pushViewController(edit, animated: true)
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
            title: "Sair da conta?",
            message: "Você vai sair desta conta neste dispositivo.",
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
        alert.addAction(UIAlertAction(title: "Sair da conta", style: .destructive) { [weak self] _ in
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
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("verse2note-dados.json")
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
            title: "Excluir conta?",
            message: "Isso remove permanentemente suas notas, grupos e preferências. Não pode ser desfeito.",
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
        alert.addAction(UIAlertAction(title: "Excluir conta", style: .destructive) { [weak self] _ in
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
                    title: "Conta apagada",
                    message: "Sua conta foi removida.",
                    preferredStyle: .alert
                )
                done.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
                    self?.presentSignIn()
                })
                present(done, animated: true)
            } catch {
                presentError(error.localizedDescription)
            }
        }
    }

    private func openHelp() {
        guard let url = URL(string: "https://verse2note.com/about") else { return }
        UIApplication.shared.open(url)
    }

    private func presentError(_ message: String) {
        let alert = UIAlertController(title: "Erro", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func themeLabel(_ theme: String) -> String {
        switch theme {
        case "light": return "Claro"
        case "dark": return "Escuro"
        default: return "Sistema"
        }
    }

    private func languageLabel(_ locale: String) -> String {
        switch locale {
        case "en": return "English"
        case "es": return "Español"
        default: return "Português"
        }
    }

    private func bibleAppLabel(_ appId: String) -> String {
        ProfileBibleCatalog.name(for: appId)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutHeader()
    }
}
