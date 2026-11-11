import UIKit

/// Perfil → Conta → Contas conectadas.
final class ConnectedIdentitiesViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let refresh = UIRefreshControl()
    private var identities: [ConnectedIdentityDTO] = ConnectedIdentitiesLogic.orderedIdentities([])
    private var minPasswordLength = NativeEmailAuthForm.minPasswordLength
    private var loadError: String?
    private var busy = false
    private let onChanged: () -> Void

    init(onChanged: @escaping () -> Void = {}) {
        self.onChanged = onChanged
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        KCChrome.styleScreen(view)
        title = String(localized: "Contas conectadas")
        navigationItem.largeTitleDisplayMode = .never
        if let nav = navigationController {
            KCChrome.style(navigationController: nav)
        }

        tableView.translatesAutoresizingMaskIntoConstraints = false
        KCChrome.styleGroupedTable(tableView)
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
        reload()
    }

    @objc private func reload() {
        Task { @MainActor in
            defer { refresh.endRefreshing() }
            do {
                let response = try await NativeAPIClient.listIdentities()
                identities = ConnectedIdentitiesLogic.orderedIdentities(response.identities ?? [])
                if let min = response.minPasswordLength, min > 0 {
                    minPasswordLength = min
                }
                loadError = nil
            } catch {
                loadError = error.localizedDescription
            }
            tableView.reloadData()
        }
    }

    private var linkedCount: Int { identities.filter(\.linked).count }

    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        identities.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        String(localized: "Métodos de entrada")
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if let loadError { return loadError }
        return String(localized: "Ligue Apple, Google ou email e senha à mesma conta Katecheo. Mantenha pelo menos um método.")
    }

    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        guard let header = view as? UITableViewHeaderFooterView else { return }
        header.textLabel?.font = KCDesign.sectionHeader()
        header.textLabel?.textColor = .secondaryLabel
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let row = identities[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = row.provider.title
        config.image = UIImage(systemName: row.provider.systemImage)
        config.imageProperties.tintColor = KCDesign.accent
        if row.linked {
            let masked = row.emailMasked?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            config.secondaryText = masked.isEmpty
                ? ConnectedIdentitiesLogic.localizedStatus(linked: true)
                : "\(ConnectedIdentitiesLogic.localizedStatus(linked: true)) · \(masked)"
            cell.accessoryType = .none
            let badge = UILabel()
            badge.text = String(localized: "Conectado")
            badge.font = KCDesign.caption()
            badge.textColor = KCDesign.accent
            badge.sizeToFit()
            cell.accessoryView = badge
        } else {
            config.secondaryText = ConnectedIdentitiesLogic.localizedStatus(linked: false)
            cell.accessoryView = nil
            cell.accessoryType = .disclosureIndicator
        }
        cell.contentConfiguration = config
        cell.selectionStyle = busy ? .none : .default
        cell.kcApplyThemedGroupedCell()
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !busy else { return }
        let row = identities[indexPath.row]
        KCHaptics.selection()
        if row.linked {
            if row.provider == .password {
                presentLinkedPasswordActions(canUnlink: ConnectedIdentitiesLogic.canUnlink(
                    identities: identities,
                    provider: .password
                ))
                return
            }
            if ConnectedIdentitiesLogic.canUnlink(identities: identities, provider: row.provider) {
                confirmUnlink(row.provider)
            } else {
                presentMessage(
                    String(localized: "Mantenha pelo menos um método de entrada."),
                    title: String(localized: "Não é possível desligar")
                )
            }
            return
        }
        switch row.provider {
        case .apple: linkApple()
        case .google: linkGoogle()
        case .password: presentSetPassword(hasPassword: false)
        }
    }

    private func presentLinkedPasswordActions(canUnlink: Bool) {
        let alert = UIAlertController(
            title: String(localized: "Email e senha"),
            message: nil,
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: String(localized: "Alterar senha"), style: .default) { [weak self] _ in
            self?.presentSetPassword(hasPassword: true)
        })
        if canUnlink {
            alert.addAction(UIAlertAction(title: String(localized: "Desligar"), style: .destructive) { [weak self] _ in
                self?.confirmUnlink(.password)
            })
        }
        alert.addAction(UIAlertAction(title: String(localized: "Cancelar"), style: .cancel))
        KCConfirmation.presentActionSheet(alert, from: self, sourceView: tableView, sourceRect: nil)
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let row = identities[indexPath.row]
        guard row.linked,
              ConnectedIdentitiesLogic.canUnlink(identities: identities, provider: row.provider)
        else { return nil }
        let unlink = UIContextualAction.kcIconOnly(
            style: .destructive,
            systemName: "link.badge.minus",
            accessibilityLabel: String(localized: "Desligar")
        ) { [weak self] _, _, done in
            self?.confirmUnlink(row.provider)
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [unlink])
    }

    private func setBusy(_ on: Bool) {
        busy = on
        navigationItem.rightBarButtonItem = on
            ? UIBarButtonItem(customView: {
                let spinner = UIActivityIndicatorView(style: .medium)
                spinner.startAnimating()
                return spinner
            }())
            : nil
        tableView.allowsSelection = !on
    }

    private func linkApple() {
        setBusy(true)
        Task { @MainActor in
            defer { setBusy(false) }
            do {
                try await NativeLoginService.shared.linkApple(from: self)
                await refreshAfterChange()
            } catch NativeLoginService.LoginError.cancelled {
                /* ignore */
            } catch {
                presentMessage(Self.mapError(error, provider: .apple))
            }
        }
    }

    private func linkGoogle() {
        setBusy(true)
        Task { @MainActor in
            defer { setBusy(false) }
            do {
                try await NativeLoginService.shared.linkGoogle(from: self)
                await refreshAfterChange()
            } catch NativeLoginService.LoginError.cancelled {
                /* ignore */
            } catch {
                presentMessage(Self.mapError(error, provider: .google))
            }
        }
    }

    private func presentSetPassword(hasPassword: Bool) {
        let alert = UIAlertController(
            title: hasPassword
                ? String(localized: "Alterar senha")
                : String(localized: "Definir senha"),
            message: hasPassword
                ? String(localized: "Informe a senha atual e a nova senha.")
                : String(localized: "Crie uma senha para entrar com o email desta conta."),
            preferredStyle: .alert
        )
        if hasPassword {
            alert.addTextField { field in
                field.placeholder = String(localized: "Senha atual")
                field.isSecureTextEntry = true
                field.textContentType = .password
            }
        }
        alert.addTextField { field in
            field.placeholder = String(localized: "Nova senha")
            field.isSecureTextEntry = true
            field.textContentType = hasPassword ? .newPassword : .newPassword
        }
        alert.addTextField { field in
            field.placeholder = String(localized: "Confirmar senha")
            field.isSecureTextEntry = true
            field.textContentType = .newPassword
        }
        alert.addAction(UIAlertAction(title: String(localized: "Cancelar"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "Salvar"), style: .default) { [weak self] _ in
            guard let self else { return }
            let fields = alert.textFields ?? []
            let current: String
            let password: String
            let confirm: String
            if hasPassword {
                current = fields[safe: 0]?.text ?? ""
                password = fields[safe: 1]?.text ?? ""
                confirm = fields[safe: 2]?.text ?? ""
            } else {
                current = ""
                password = fields[safe: 0]?.text ?? ""
                confirm = fields[safe: 1]?.text ?? ""
            }
            let validation = ConnectedIdentitiesLogic.validateSetPassword(
                password: password,
                passwordConfirm: confirm,
                currentPassword: current,
                hasPassword: hasPassword,
                minLength: self.minPasswordLength
            )
            guard validation.isValid else {
                self.presentMessage(validation.firstMessage ?? String(localized: "Verifique os campos."))
                return
            }
            self.submitPassword(password, currentPassword: hasPassword ? current : nil)
        })
        present(alert, animated: true)
    }

    private func submitPassword(_ password: String, currentPassword: String?) {
        setBusy(true)
        Task { @MainActor in
            defer { setBusy(false) }
            do {
                try await NativeAPIClient.setIdentityPassword(
                    password: password,
                    currentPassword: currentPassword
                )
                await refreshAfterChange()
            } catch {
                presentMessage(Self.mapError(error, provider: .password))
            }
        }
    }

    private func confirmUnlink(_ provider: ConnectedIdentityProvider) {
        let alert = UIAlertController(
            title: String(localized: "Desligar método?"),
            message: String(localized: "Você poderá ligar de novo depois. Mantenha pelo menos um método de entrada."),
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: String(localized: "Cancelar"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "Desligar"), style: .destructive) { [weak self] _ in
            self?.performUnlink(provider)
        })
        let index = identities.firstIndex(where: { $0.provider == provider }) ?? 0
        let rect = tableView.rectForRow(at: IndexPath(row: index, section: 0))
        KCConfirmation.presentActionSheet(
            alert,
            from: self,
            sourceView: tableView,
            sourceRect: rect.isEmpty ? nil : rect
        )
    }

    private func performUnlink(_ provider: ConnectedIdentityProvider) {
        setBusy(true)
        Task { @MainActor in
            defer { setBusy(false) }
            do {
                try await NativeAPIClient.unlinkIdentity(provider: provider)
                await refreshAfterChange()
            } catch {
                presentMessage(Self.mapError(error, provider: provider))
            }
        }
    }

    private func refreshAfterChange() async {
        do {
            let response = try await NativeAPIClient.listIdentities()
            identities = ConnectedIdentitiesLogic.orderedIdentities(response.identities ?? [])
            if let min = response.minPasswordLength, min > 0 {
                minPasswordLength = min
            }
            loadError = nil
            tableView.reloadData()
            onChanged()
            NotificationCenter.default.post(name: .nativeSessionDidChange, object: nil)
        } catch {
            loadError = error.localizedDescription
            tableView.reloadData()
        }
    }

    private func presentMessage(_ message: String, title: String = String(localized: "Atenção")) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
        present(alert, animated: true)
    }

    private static func mapError(_ error: Error, provider: ConnectedIdentityProvider) -> String {
        if let api = error as? NativeAPIClient.APIError, case .http(let status, let body) = api {
            let code: String?
            if let data = body.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(ConnectedIdentitiesResponse.self, from: data)
            {
                code = decoded.error
            } else if body.contains("identity_in_use") {
                code = "identity_in_use"
            } else if body.contains("last_method") {
                code = "last_method"
            } else {
                code = body
            }
            return ConnectedIdentitiesLogic.localizedError(code: code, provider: provider, status: status)
        }
        if let login = error as? NativeLoginService.LoginError {
            return login.errorDescription
                ?? ConnectedIdentitiesLogic.localizedError(code: nil, provider: provider)
        }
        return error.localizedDescription
    }

    // MARK: - Testing hooks

    var testing_identities: [ConnectedIdentityDTO] { identities }

    func testing_setIdentities(_ rows: [ConnectedIdentityDTO]) {
        identities = ConnectedIdentitiesLogic.orderedIdentities(rows)
        tableView.reloadData()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
