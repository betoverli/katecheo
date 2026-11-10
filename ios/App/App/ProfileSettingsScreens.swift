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

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        v2nApplyTabBarScrollClearanceIfNeeded()
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
        cell.v2nApplyThemedGroupedCell()
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
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "editorLight")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        v2nApplyTabBarScrollClearanceIfNeeded()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? options.count : 1
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 1 ? String(localized: "Editor") : nil
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 {
            return String(localized: "A aparência se aplica às telas nativas. O tema fica salvo na sua conta.")
        }
        return String(localized: "Só enquanto edita uma nota. O restante do app segue a Aparência.")
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 1 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "editorLight", for: indexPath)
            var config = cell.defaultContentConfiguration()
            config.text = String(localized: "Editor sempre claro")
            config.secondaryText = String(localized: "Manter a edição de notas no modo Claro")
            config.image = UIImage(systemName: "sun.max.circle")
            cell.contentConfiguration = config
            cell.selectionStyle = .none
            let toggle = UISwitch()
            toggle.isOn = AppAppearance.keepEditorInLightMode
            toggle.addTarget(self, action: #selector(editorLightChanged(_:)), for: .valueChanged)
            cell.accessoryView = toggle
            cell.v2nApplyThemedGroupedCell()
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: "theme", for: indexPath)
        let option = options[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = option.title
        config.image = UIImage(systemName: option.symbol)
        cell.contentConfiguration = config
        cell.accessoryType = theme == option.id ? .checkmark : .none
        cell.accessoryView = nil
        cell.v2nApplyThemedGroupedCell()
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 0 else { return }
        let option = options[indexPath.row]
        theme = option.id
        tableView.reloadData()
        AppAppearance.setTheme(option.id)
        Task { @MainActor in
            do {
                _ = try await NativeAPIClient.patchPrefs(["theme": option.id])
                onSaved()
            } catch {
                presentSaveError(on: self, error)
            }
        }
    }

    @objc private func editorLightChanged(_ toggle: UISwitch) {
        AppAppearance.setKeepEditorInLightMode(toggle.isOn)
        V2NHaptics.selection()
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

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        v2nApplyTabBarScrollClearanceIfNeeded()
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
        cell.v2nApplyThemedGroupedCell()
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
        ReferencePrefs.copyLocale = option.id
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

/// Profile → App de Bíblia. Single scrolling table so Translation / Open with clear the floating tab bar (TF214).
final class ProfileBibleViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource, UITableViewDelegate, UITableViewDataSource {
    private var prefs: NativeAPIClient.PrefsDTO
    private let onSaved: () -> Void
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var logoCollection: UICollectionView!
    private var logoHeightConstraint: NSLayoutConstraint?
    private var headerContainer: UIView!

    init(prefs: NativeAPIClient.PrefsDTO, onSaved: @escaping () -> Void) {
        self.prefs = prefs
        self.onSaved = onSaved
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        V2NChrome.styleScreen(view)
        title = String(localized: "App de Bíblia")
        if let nav = navigationController {
            V2NChrome.applyNavigationBarAppearance(to: nav.navigationBar)
            nav.view.backgroundColor = V2NDesign.screenBackground
        }

        tableView.translatesAutoresizingMaskIntoConstraints = false
        V2NChrome.styleGroupedTable(tableView)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "opt")
        tableView.alwaysBounceVertical = true
        tableView.keyboardDismissMode = .onDrag
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        buildHeader()
        tableView.tableHeaderView = headerContainer
    }

    private func buildHeader() {
        let header = UIView()
        header.backgroundColor = .clear

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = String(localized: "Aplicativo").uppercased()
        title.font = V2NDesign.sectionHeader()
        title.textColor = .secondaryLabel
        title.accessibilityTraits = .header

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
        let logos = UICollectionView(frame: .zero, collectionViewLayout: layout)
        logos.translatesAutoresizingMaskIntoConstraints = false
        logos.backgroundColor = .clear
        logos.isScrollEnabled = false
        logos.delegate = self
        logos.dataSource = self
        logos.register(V2NBibleAppLogoCell.self, forCellWithReuseIdentifier: V2NBibleAppLogoCell.reuseId)

        header.addSubview(title)
        header.addSubview(logos)
        let logoHeight = logos.heightAnchor.constraint(equalToConstant: logoGridHeight(columns: 3))
        logoHeightConstraint = logoHeight
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: header.topAnchor, constant: V2NDesign.Space.sm),
            title.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 20),
            title.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -20),

            logos.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            logos.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            logos.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            logos.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -V2NDesign.Space.xs),
            logoHeight,
        ])

        logoCollection = logos
        headerContainer = header
        relayoutHeader(width: view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width)
    }

    private func logoGridHeight(columns: Int) -> CGFloat {
        let cols = max(columns, 1)
        let rows = Int(ceil(Double(ProfileBibleCatalog.apps.count) / Double(cols)))
        return CGFloat(rows) * 118 + 16
    }

    private func relayoutHeader(width: CGFloat) {
        guard let headerContainer, width > 0 else { return }
        let cols = width > 500 ? 4 : 3
        logoHeightConstraint?.constant = logoGridHeight(columns: cols)
        let target = CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
        let height = headerContainer.systemLayoutSizeFitting(
            target,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        let next = CGRect(x: 0, y: 0, width: width, height: height)
        if abs(headerContainer.frame.height - height) > 0.5 || abs(headerContainer.frame.width - width) > 0.5 {
            headerContainer.frame = next
            tableView.tableHeaderView = headerContainer
        }
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
        relayoutHeader(width: tableView.bounds.width)
        v2nApplyTabBarScrollClearance(to: tableView)
    }

    // MARK: Logo grid

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        ProfileBibleCatalog.apps.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: V2NBibleAppLogoCell.reuseId, for: indexPath) as? V2NBibleAppLogoCell else {
            return UICollectionViewCell()
        }
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
        // "Abertura" localizes to "Open with" — keep source string for catalog continuity.
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
        cell.v2nApplyThemedGroupedCell()
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

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        v2nApplyTabBarScrollClearanceIfNeeded()
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
            cell.v2nApplyThemedGroupedCell()
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
        cell.v2nApplyThemedGroupedCell()
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
