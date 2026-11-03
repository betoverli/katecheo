import UIKit

// MARK: - Shared helpers

enum ProfileBibleCatalog {
    static let apps: [(id: String, name: String)] = [
        ("youversion", "YouVersion (Bible App)"),
        ("tecarta", "Life Bible (Tecarta)"),
        ("logos", "Logos"),
        ("olive-tree", "Olive Tree"),
        ("bible-gateway", "Bible Gateway"),
        ("blue-letter", "Blue Letter Bible"),
        ("esv", "ESV Bible"),
        ("biblia-online", "Bíblia Online"),
        ("bible-hub", "Bible Hub"),
        ("accordance", "Accordance"),
        ("e-sword", "e-Sword"),
        ("mysword", "MySword"),
        ("jw-library", "JW Library"),
    ]

    static let translations: [(id: String, name: String)] = [
        ("nvi-pt", "NVI — Nova Versão Internacional"),
        ("ntlh", "NTLH"),
        ("arc", "ARC — Almeida Revista e Corrigida"),
        ("naa", "NAA"),
        ("ara", "ARA"),
        ("niv", "NIV"),
        ("esv", "ESV"),
        ("kjv", "KJV"),
        ("rvr1960", "RVR1960"),
    ]

    static func name(for appId: String) -> String {
        apps.first(where: { $0.id == appId })?.name ?? appId
    }
}

private func presentSaveError(on vc: UIViewController, _ error: Error) {
    let message: String
    if let api = error as? NativeAPIClient.APIError, case .http(let code, _) = api, code == 409 {
        message = "Esse @ já está em uso."
    } else {
        message = error.localizedDescription
    }
    let alert = UIAlertController(title: "Não foi possível salvar", message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    vc.present(alert, animated: true)
}

// MARK: - Edit profile

final class ProfileEditViewController: UITableViewController {
    private var me: NativeAPIClient.MeDTO
    private let onSaved: () -> Void
    private var firstName: String
    private var lastName: String
    private var handle: String
    private var email: String
    private var saving = false

    init(me: NativeAPIClient.MeDTO, onSaved: @escaping () -> Void) {
        self.me = me
        self.onSaved = onSaved
        self.firstName = me.prefs.firstName
        self.lastName = me.prefs.lastName
        self.handle = me.prefs.handle
        self.email = me.prefs.profileEmail.isEmpty ? (me.email ?? "") : me.prefs.profileEmail
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        v2nApplyGroupedChrome()
        title = "Editar perfil"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Salvar",
            style: .done,
            target: self,
            action: #selector(save)
        )
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "field")
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 4 }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "Nome e contato"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "field", for: indexPath)
        cell.selectionStyle = .none
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }

        let field = UITextField(frame: .zero)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.clearButtonMode = .whileEditing
        field.autocapitalizationType = .words
        field.tag = indexPath.row
        field.addTarget(self, action: #selector(fieldChanged(_:)), for: .editingChanged)

        switch indexPath.row {
        case 0:
            field.placeholder = "Nome"
            field.text = firstName
            field.textContentType = .givenName
        case 1:
            field.placeholder = "Sobrenome"
            field.text = lastName
            field.textContentType = .familyName
        case 2:
            field.placeholder = "usuario"
            field.text = handle
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.keyboardType = .asciiCapable
            let prefix = UILabel()
            prefix.text = "@ "
            prefix.textColor = .secondaryLabel
            prefix.sizeToFit()
            field.leftView = prefix
            field.leftViewMode = .always
        default:
            field.placeholder = "E-mail"
            field.text = email
            field.keyboardType = .emailAddress
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.textContentType = .emailAddress
        }

        cell.contentView.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
            field.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
            field.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12),
            field.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -12),
        ])
        return cell
    }

    @objc private func fieldChanged(_ field: UITextField) {
        let value = field.text ?? ""
        switch field.tag {
        case 0: firstName = value
        case 1: lastName = value
        case 2:
            handle = value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "^@+", with: "", options: .regularExpression)
                .lowercased()
                .filter { $0.isLetter || $0.isNumber || $0 == "_" }
        default: email = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    @objc private func save() {
        guard !saving else { return }
        saving = true
        navigationItem.rightBarButtonItem?.isEnabled = false
        Task { @MainActor in
            defer {
                saving = false
                navigationItem.rightBarButtonItem?.isEnabled = true
            }
            do {
                _ = try await NativeAPIClient.patchMe([
                    "firstName": firstName,
                    "lastName": lastName,
                    "handle": handle,
                    "profileEmail": email,
                ])
                onSaved()
                navigationController?.popViewController(animated: true)
            } catch {
                presentSaveError(on: self, error)
            }
        }
    }
}

// MARK: - Theme

final class ProfileThemeViewController: UITableViewController {
    private var theme: String
    private let onSaved: () -> Void
    private let options: [(id: String, title: String, symbol: String)] = [
        ("system", "Sistema", "circle.lefthalf.filled"),
        ("light", "Claro", "sun.max"),
        ("dark", "Escuro", "moon.fill"),
    ]

    init(theme: String, onSaved: @escaping () -> Void) {
        self.theme = theme
        self.onSaved = onSaved
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        v2nApplyGroupedChrome()
        title = "Aparência"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "theme")
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        options.count
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "A aparência se aplica às telas nativas. O tema fica salvo na sua conta."
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "theme", for: indexPath)
        let option = options[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = option.title
        config.image = UIImage(systemName: option.symbol)
        cell.contentConfiguration = config
        cell.accessoryType = theme == option.id ? .checkmark : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let option = options[indexPath.row]
        theme = option.id
        tableView.reloadData()
        applyThemeLocally(option.id)
        Task { @MainActor in
            do {
                _ = try await NativeAPIClient.patchPrefs(["theme": option.id])
                onSaved()
            } catch {
                presentSaveError(on: self, error)
            }
        }
    }

    private func applyThemeLocally(_ theme: String) {
        guard let scene = view.window?.windowScene else { return }
        let style: UIUserInterfaceStyle
        switch theme {
        case "light": style = .light
        case "dark": style = .dark
        default: style = .unspecified
        }
        for window in scene.windows {
            window.overrideUserInterfaceStyle = style
        }
    }
}

// MARK: - Language

final class ProfileLanguageViewController: UITableViewController {
    private var prefs: NativeAPIClient.PrefsDTO
    private let onSaved: () -> Void
    private let locales: [(id: String, title: String)] = [
        ("pt", "Português"),
        ("en", "English"),
        ("es", "Español"),
    ]

    init(prefs: NativeAPIClient.PrefsDTO, onSaved: @escaping () -> Void) {
        self.prefs = prefs
        self.onSaved = onSaved
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        v2nApplyGroupedChrome()
        title = "Idioma"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "lang")
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        locales.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "Navegação" : "Referências"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "lang", for: indexPath)
        let option = locales[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = option.title
        cell.contentConfiguration = config
        let selected = indexPath.section == 0 ? prefs.locale : prefs.copyLocale
        cell.accessoryType = selected == option.id ? .checkmark : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let option = locales[indexPath.row]
        let key = indexPath.section == 0 ? "locale" : "copyLocale"
        if indexPath.section == 0 {
            prefs.locale = option.id
        } else {
            prefs.copyLocale = option.id
        }
        tableView.reloadData()
        Task { @MainActor in
            do {
                _ = try await NativeAPIClient.patchPrefs([key: option.id])
                onSaved()
            } catch {
                presentSaveError(on: self, error)
            }
        }
    }
}

// MARK: - Bible

final class ProfileBibleViewController: UITableViewController {
    private var prefs: NativeAPIClient.PrefsDTO
    private let onSaved: () -> Void

    init(prefs: NativeAPIClient.PrefsDTO, onSaved: @escaping () -> Void) {
        self.prefs = prefs
        self.onSaved = onSaved
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        v2nApplyGroupedChrome()
        title = "App de Bíblia"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "bible")
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 3 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return ProfileBibleCatalog.apps.count
        case 1: return ProfileBibleCatalog.translations.count
        default: return 2
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "Aplicativo"
        case 1: return "Tradução"
        default: return "Abertura"
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "bible", for: indexPath)
        var config = cell.defaultContentConfiguration()
        switch indexPath.section {
        case 0:
            let app = ProfileBibleCatalog.apps[indexPath.row]
            config.text = app.name
            cell.accessoryType = prefs.appId == app.id ? .checkmark : .none
        case 1:
            let tr = ProfileBibleCatalog.translations[indexPath.row]
            config.text = tr.name
            cell.accessoryType = prefs.translationId == tr.id ? .checkmark : .none
        default:
            if indexPath.row == 0 {
                config.text = "Preferir o app"
                cell.accessoryType = prefs.preferNative ? .checkmark : .none
            } else {
                config.text = "Preferir a web"
                cell.accessoryType = !prefs.preferNative ? .checkmark : .none
            }
        }
        cell.contentConfiguration = config
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        var patch: [String: Any] = [:]
        switch indexPath.section {
        case 0:
            let app = ProfileBibleCatalog.apps[indexPath.row]
            prefs.appId = app.id
            patch["appId"] = app.id
        case 1:
            let tr = ProfileBibleCatalog.translations[indexPath.row]
            prefs.translationId = tr.id
            patch["translationId"] = tr.id
        default:
            prefs.preferNative = indexPath.row == 0
            patch["preferNative"] = prefs.preferNative
        }
        tableView.reloadData()
        Task { @MainActor in
            do {
                _ = try await NativeAPIClient.patchPrefs(patch)
                onSaved()
            } catch {
                presentSaveError(on: self, error)
            }
        }
    }
}

// MARK: - Notifications

final class ProfileNotifyViewController: UITableViewController {
    private var notify: NativeAPIClient.NotifyPrefsDTO
    private let onSaved: () -> Void

    private let rows: [(key: String, title: String, subtitle: String)] = [
        ("reading", "Planos de leitura", "Lembretes dos seus planos"),
        ("friends", "Amigos", "Pedidos e aceitações"),
        ("shares", "Compartilhamentos", "Notas e coleções compartilhadas"),
        ("groups", "Grupos", "Atividade nos seus grupos"),
    ]

    init(notify: NativeAPIClient.NotifyPrefsDTO, onSaved: @escaping () -> Void) {
        self.notify = notify
        self.onSaved = onSaved
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        v2nApplyGroupedChrome()
        title = "Avisos"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "notify")
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 1 : rows.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "Dispositivo" : "Tipos de alerta"
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 {
            let count = notify.apnsDevices ?? 0
            return count > 0
                ? "Este dispositivo pode receber notificações push (APNs)."
                : "Ative as notificações nas Configurações do iOS se quiser alertas push."
        }
        return nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "notify", for: indexPath)
        var config = cell.defaultContentConfiguration()
        if indexPath.section == 0 {
            let count = notify.apnsDevices ?? 0
            config.text = "Ativar push neste iPhone"
            config.secondaryText = count > 0 ? "Registrado (\(count))" : "Toque para pedir permissão"
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
            cell.contentConfiguration = config
            return cell
        }

        let row = rows[indexPath.row]
        config.text = row.title
        config.secondaryText = row.subtitle
        cell.contentConfiguration = config
        cell.selectionStyle = .none
        let toggle = UISwitch()
        toggle.isOn = value(for: row.key)
        toggle.tag = indexPath.row
        toggle.addTarget(self, action: #selector(toggleChanged(_:)), for: .valueChanged)
        cell.accessoryView = toggle
        return cell
    }

    private func value(for key: String) -> Bool {
        switch key {
        case "reading": return notify.reading
        case "friends": return notify.friends
        case "shares": return notify.shares
        case "groups": return notify.groups
        default: return true
        }
    }

    private func setValue(_ on: Bool, for key: String) {
        switch key {
        case "reading": notify.reading = on
        case "friends": notify.friends = on
        case "shares": notify.shares = on
        case "groups": notify.groups = on
        default: break
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 0 else { return }
        Task { @MainActor in
            let ok = await NativePushService.shared.enable()
            if ok {
                // Refresh device count from server after registration settles.
                try? await Task.sleep(nanoseconds: 800_000_000)
                if let latest = try? await NativeAPIClient.getNotifyPrefs() {
                    notify = latest
                }
                tableView.reloadSections(IndexSet(integer: 0), with: .automatic)
                onSaved()
            } else {
                let alert = UIAlertController(
                    title: "Notificações",
                    message: "Permissão negada. Ative nas Configurações do iOS se quiser alertas.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
            }
        }
    }

    @objc private func toggleChanged(_ sender: UISwitch) {
        let row = rows[sender.tag]
        setValue(sender.isOn, for: row.key)
        Task { @MainActor in
            do {
                notify = try await NativeAPIClient.patchNotifyPrefs([row.key: sender.isOn])
                onSaved()
            } catch {
                sender.isOn.toggle()
                setValue(sender.isOn, for: row.key)
                presentSaveError(on: self, error)
            }
        }
    }
}
