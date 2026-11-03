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
        ("biblia-online", String(localized: "Bíblia Online")),
        ("bible-hub", "Bible Hub"),
        ("accordance", "Accordance"),
        ("e-sword", "e-Sword"),
        ("mysword", "MySword"),
        ("jw-library", "JW Library"),
    ]

    static let translations: [(id: String, name: String)] = [
        ("nvi-pt", String(localized: "NVI — Nova Versão Internacional")),
        ("ntlh", "NTLH"),
        ("arc", String(localized: "ARC — Almeida Revista e Corrigida")),
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
        message = String(localized: "Esse @ já está em uso.")
    } else {
        message = error.localizedDescription
    }
    let alert = UIAlertController(title: String(localized: "Não foi possível salvar"), message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
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
        title = String(localized: "Editar perfil")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: String(localized: "Salvar"),
            style: .done,
            target: self,
            action: #selector(save)
        )
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "field")
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 4 }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        String(localized: "Nome e contato")
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
            field.placeholder = String(localized: "Nome")
            field.text = firstName
            field.textContentType = .givenName
        case 1:
            field.placeholder = String(localized: "Sobrenome")
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
            field.placeholder = String(localized: "E-mail")
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
        ("system", String(localized: "Sistema"), "circle.lefthalf.filled"),
        ("light", String(localized: "Claro"), "sun.max"),
        ("dark", String(localized: "Escuro"), "moon.fill"),
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
        title = String(localized: "Aparência")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "theme")
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        options.count
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        String(localized: "A aparência se aplica às telas nativas. O tema fica salvo na sua conta.")
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
    private let copyLocales: [(id: String, title: String)] = [
        ("pt", String(localized: "Português")),
        ("en", String(localized: "English")),
        ("es", String(localized: "Español")),
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
        title = String(localized: "Idioma")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "lang")
        syncInterfaceLocaleToServer()
    }

    /// Interface language follows the iPhone; keep server `locale` in sync for prefs consumers.
    private func syncInterfaceLocaleToServer() {
        let device = AppLocale.apiCode
        guard prefs.locale != device else { return }
        prefs.locale = device
        Task { @MainActor in
            do {
                _ = try await NativeAPIClient.patchPrefs(["locale": device])
                onSaved()
            } catch {
                // Non-fatal: UI still follows the system language.
            }
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 1 : copyLocales.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? String(localized: "Interface") : String(localized: "Referências")
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 {
            return String(localized: "O idioma da interface segue o do iPhone. Para mudar, abra as Configurações do app e escolha Português (Brasil), English ou Español.")
        }
        return String(localized: "Nomes e siglas ao copiar um versículo.")
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "lang", for: indexPath)
        var config = cell.defaultContentConfiguration()
        if indexPath.section == 0 {
            config.text = String(localized: "Abrir Configurações do idioma")
            config.secondaryText = AppLocale.interfaceLanguageLabel
            config.image = UIImage(systemName: "gearshape")
            cell.accessoryType = .disclosureIndicator
        } else {
            let option = copyLocales[indexPath.row]
            config.text = option.title
            cell.accessoryType = prefs.copyLocale == option.id ? .checkmark : .none
        }
        cell.contentConfiguration = config
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            AppLocale.openSystemSettings()
            return
        }
        let option = copyLocales[indexPath.row]
        prefs.copyLocale = option.id
        tableView.reloadData()
        Task { @MainActor in
            do {
                _ = try await NativeAPIClient.patchPrefs(["copyLocale": option.id])
                onSaved()
            } catch {
                presentSaveError(on: self, error)
            }
        }
    }
}

// MARK: - Bible

final class ProfileBibleViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource, UITableViewDelegate, UITableViewDataSource {
    private var prefs: NativeAPIClient.PrefsDTO
    private let onSaved: () -> Void
    private var logoCollection: UICollectionView!
    private var logoHeightConstraint: NSLayoutConstraint?
    private let optionsTable = UITableView(frame: .zero, style: .insetGrouped)
    private let scroll = UIScrollView()
    private let content = UIStackView()

    init(prefs: NativeAPIClient.PrefsDTO, onSaved: @escaping () -> Void) {
        self.prefs = prefs
        self.onSaved = onSaved
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        V2NChrome.styleCanvas(view)
        title = String(localized: "App de Bíblia")

        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        view.addSubview(scroll)

        content.axis = .vertical
        content.spacing = V2NDesign.Space.sm
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)

        content.addArrangedSubview(makeSectionHeader(String(localized: "Aplicativo")))

        let layout = UICollectionViewCompositionalLayout { _, env in
            let width = env.container.effectiveContentSize.width
            let cols = width > 500 ? 4 : 3
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1 / CGFloat(cols)),
                heightDimension: .absolute(118)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            item.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(118)),
                subitem: item,
                count: cols
            )
            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 10, bottom: 8, trailing: 10)
            return section
        }
        logoCollection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        logoCollection.translatesAutoresizingMaskIntoConstraints = false
        logoCollection.backgroundColor = .clear
        logoCollection.isScrollEnabled = false
        logoCollection.delegate = self
        logoCollection.dataSource = self
        logoCollection.register(V2NBibleAppLogoCell.self, forCellWithReuseIdentifier: V2NBibleAppLogoCell.reuseId)
        content.addArrangedSubview(logoCollection)

        optionsTable.translatesAutoresizingMaskIntoConstraints = false
        V2NChrome.styleGroupedTable(optionsTable)
        optionsTable.delegate = self
        optionsTable.dataSource = self
        optionsTable.isScrollEnabled = false
        optionsTable.register(UITableViewCell.self, forCellReuseIdentifier: "opt")
        content.addArrangedSubview(optionsTable)

        let logoHeight = logoCollection.heightAnchor.constraint(equalToConstant: logoGridHeight(columns: 3))
        logoHeightConstraint = logoHeight

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: V2NDesign.Space.sm),
            content.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -V2NDesign.Space.xl),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),

            logoHeight,
            optionsTable.heightAnchor.constraint(equalToConstant: optionsTableHeight()),
        ])
    }

    private func makeSectionHeader(_ text: String) -> UIView {
        let box = UIView()
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text.uppercased()
        label.font = V2NDesign.sectionHeader()
        label.textColor = .secondaryLabel
        box.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -20),
            label.topAnchor.constraint(equalTo: box.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -4),
            box.heightAnchor.constraint(greaterThanOrEqualToConstant: 28),
        ])
        return box
    }

    private func logoGridHeight(columns: Int) -> CGFloat {
        let cols = max(columns, 1)
        let rows = Int(ceil(Double(ProfileBibleCatalog.apps.count) / Double(cols)))
        return CGFloat(rows) * 118 + 16
    }

    private func optionsTableHeight() -> CGFloat {
        let rows = ProfileBibleCatalog.translations.count + 2
        return CGFloat(rows) * 48 + 88
    }

    private func assetName(for appId: String) -> String {
        "BibleApp_" + appId.replacingOccurrences(of: "-", with: "_")
    }

    private func patchPrefs(_ patch: [String: Any]) {
        Task { @MainActor in
            do {
                _ = try await NativeAPIClient.patchPrefs(patch)
                onSaved()
            } catch {
                presentSaveError(on: self, error)
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let cols = view.bounds.width > 500 ? 4 : 3
        logoHeightConstraint?.constant = logoGridHeight(columns: cols)
    }

    // MARK: Logo grid

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        ProfileBibleCatalog.apps.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: V2NBibleAppLogoCell.reuseId, for: indexPath) as! V2NBibleAppLogoCell
        let app = ProfileBibleCatalog.apps[indexPath.item]
        let image = UIImage(named: assetName(for: app.id))
        cell.configure(name: shortName(app.name), image: image, selected: prefs.appId == app.id)
        return cell
    }

    private func shortName(_ name: String) -> String {
        if name.hasPrefix("YouVersion") { return "YouVersion" }
        if name.hasPrefix("Life Bible") { return "Tecarta" }
        return name
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        V2NHaptics.selection()
        let app = ProfileBibleCatalog.apps[indexPath.item]
        prefs.appId = app.id
        logoCollection.reloadData()
        patchPrefs(["appId": app.id])
    }

    // MARK: Options table

    func numberOfSections(in tableView: UITableView) -> Int { 2 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? ProfileBibleCatalog.translations.count : 2
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? String(localized: "Tradução") : String(localized: "Abertura")
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "opt", for: indexPath)
        var config = cell.defaultContentConfiguration()
        if indexPath.section == 0 {
            let tr = ProfileBibleCatalog.translations[indexPath.row]
            config.text = tr.name
            cell.accessoryType = prefs.translationId == tr.id ? .checkmark : .none
        } else if indexPath.row == 0 {
            config.text = String(localized: "Preferir o app")
            cell.accessoryType = prefs.preferNative ? .checkmark : .none
        } else {
            config.text = String(localized: "Preferir a web")
            cell.accessoryType = !prefs.preferNative ? .checkmark : .none
        }
        cell.contentConfiguration = config
        cell.tintColor = V2NDesign.accent
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            let tr = ProfileBibleCatalog.translations[indexPath.row]
            prefs.translationId = tr.id
            tableView.reloadData()
            patchPrefs(["translationId": tr.id])
        } else {
            prefs.preferNative = indexPath.row == 0
            tableView.reloadData()
            patchPrefs(["preferNative": prefs.preferNative])
        }
    }
}

// MARK: - Notifications

final class ProfileNotifyViewController: UITableViewController {
    private var notify: NativeAPIClient.NotifyPrefsDTO
    private let onSaved: () -> Void

    private let rows: [(key: String, title: String, subtitle: String)] = [
        ("reading", String(localized: "Planos de leitura"), String(localized: "Lembretes dos seus planos")),
        ("friends", String(localized: "Amigos"), String(localized: "Pedidos e aceitações")),
        ("shares", String(localized: "Compartilhamentos"), String(localized: "Notas e coleções compartilhadas")),
        ("groups", String(localized: "Grupos"), String(localized: "Atividade nos seus grupos")),
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
        title = String(localized: "Avisos")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "notify")
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 1 : rows.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? String(localized: "Dispositivo") : String(localized: "Tipos de alerta")
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 {
            let count = notify.apnsDevices ?? 0
            return count > 0
                ? String(localized: "Este dispositivo pode receber notificações push (APNs).")
                : String(localized: "Ative as notificações nas Configurações do iOS se quiser alertas push.")
        }
        return nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "notify", for: indexPath)
        var config = cell.defaultContentConfiguration()
        if indexPath.section == 0 {
            let count = notify.apnsDevices ?? 0
            config.text = String(localized: "Ativar push neste iPhone")
            config.secondaryText = count > 0 ? String(localized: "Registrado (\(count))") : String(localized: "Toque para pedir permissão")
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
                    title: String(localized: "Notificações"),
                    message: String(localized: "Permissão negada. Ative nas Configurações do iOS se quiser alertas."),
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
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
