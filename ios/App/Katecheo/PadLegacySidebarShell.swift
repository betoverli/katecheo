import UIKit

/// iPad iOS 15–17: always-on main-menu sidebar (Caderno / Grupos / Ferramentas / Perfil).
/// iPadOS 18+ uses `UITabBarController.mode = .tabSidebar` instead (see NativeRootTabBarController).
final class PadLegacySidebarShell: UISplitViewController, UISplitViewControllerDelegate {
    private let menu = PadMainMenuViewController()
    private let menuNav: UINavigationController
    private let destinations: [UIViewController]
    var selectedIndex: Int = 0 {
        didSet {
            guard oldValue != selectedIndex else { return }
            showDestination(at: selectedIndex, animated: false)
        }
    }

    init() {
        let notebook = NotebookChrome.makeTabRoot()
        notebook.tabBarItem = UITabBarItem(
            title: String(localized: "Caderno"),
            image: UIImage(systemName: "note.text"),
            tag: 0
        )
        let groups = GroupsChrome.makeTabRoot()
        groups.tabBarItem = UITabBarItem(
            title: String(localized: "Grupos"),
            image: UIImage(systemName: "person.2"),
            tag: 1
        )
        let tools = UINavigationController(rootViewController: VersesHomeViewController())
        KCChrome.style(navigationController: tools)
        tools.tabBarItem = UITabBarItem(
            title: String(localized: "Ferramentas"),
            image: UIImage(systemName: "wrench.and.screwdriver"),
            tag: 2
        )
        let profile = UINavigationController(rootViewController: ProfileViewController())
        KCChrome.style(navigationController: profile)
        profile.tabBarItem = UITabBarItem(
            title: String(localized: "Perfil"),
            image: UIImage(systemName: "person"),
            tag: 3
        )
        destinations = [notebook, groups, tools, profile]
        menuNav = UINavigationController(rootViewController: menu)
        KCChrome.style(navigationController: menuNav)
        super.init(style: .doubleColumn)
        delegate = self
        PadChrome.applyNotesFolderSplitChrome(to: self, primaryFraction: 0.26, min: 220, max: 300)
        // Sidebar stays beside content — never overlay the detail column.
        presentsWithGesture = false
        setViewController(menuNav, for: .primary)
        setViewController(notebook, for: .secondary)
        setViewController(menuNav, for: .compact)
        menu.onSelect = { [weak self] index in
            self?.selectedIndex = index
        }
        menu.selectedIndex = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        KCChrome.styleScreen(view)
        view.accessibilityIdentifier = "pad.shell.legacy"
        showDestination(at: 0, animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        PadChrome.enforceBesideDisplayMode(on: self)
    }

    private func showDestination(at index: Int, animated: Bool) {
        let clamped = min(max(0, index), destinations.count - 1)
        menu.selectedIndex = clamped
        let dest = destinations[clamped]
        setViewController(dest, for: .secondary)
        if animated {
            UIView.transition(with: view, duration: 0.2, options: .transitionCrossDissolve, animations: nil)
        }
    }

    // MARK: - Deep-link / sheet parity with NativeRootTabBarController

    @MainActor
    func presentToolsSheet(
        animated: Bool = true,
        configure: ((VersesHomeViewController) -> Void)? = nil
    ) {
        selectedIndex = 2
        if let nav = destinations[2] as? UINavigationController,
           let home = nav.viewControllers.first as? VersesHomeViewController
        {
            _ = home.view
            configure?(home)
        }
    }

    @MainActor
    func presentProfileSheet(
        animated: Bool = true,
        configure: ((ProfileViewController, UINavigationController) -> Void)? = nil
    ) {
        selectedIndex = 3
        if let nav = destinations[3] as? UINavigationController,
           let home = nav.viewControllers.first as? ProfileViewController
        {
            configure?(home, nav)
        }
    }

    var viewControllersForTabs: [UIViewController] { destinations }

    func splitViewController(
        _ svc: UISplitViewController,
        displayModeForExpandingToProposedDisplayMode proposedDisplayMode: UISplitViewController.DisplayMode
    ) -> UISplitViewController.DisplayMode {
        .oneBesideSecondary
    }
}

/// Leading main-menu list for the legacy iPad sidebar shell.
final class PadMainMenuViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    var onSelect: ((Int) -> Void)?
    var selectedIndex: Int = 0 {
        didSet { tableView.reloadData() }
    }

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let items: [(title: String, symbol: String)] = [
        (String(localized: "Caderno"), "note.text"),
        (String(localized: "Grupos"), "person.2"),
        (String(localized: "Ferramentas"), "wrench.and.screwdriver"),
        (String(localized: "Perfil"), "person"),
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        KCChrome.styleScreen(view)
        title = String(localized: "Menu")
        navigationItem.largeTitleDisplayMode = .always
        navigationController?.navigationBar.prefersLargeTitles = true
        view.accessibilityIdentifier = "pad.main.menu"

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "menu")
        tableView.backgroundColor = KCDesign.screenBackground
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 0)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "menu", for: indexPath)
        var config = cell.defaultContentConfiguration()
        let item = items[indexPath.row]
        config.text = item.title
        config.image = UIImage(systemName: item.symbol)
        config.imageProperties.tintColor = indexPath.row == selectedIndex ? KCDesign.accent : .secondaryLabel
        config.textProperties.font = KCDesign.preferred(.body, weight: indexPath.row == selectedIndex ? .semibold : .regular)
        cell.contentConfiguration = config
        cell.backgroundColor = indexPath.row == selectedIndex ? KCDesign.accentSoft : .clear
        cell.accessibilityIdentifier = "pad.main.menu.\(indexPath.row)"
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        selectedIndex = indexPath.row
        onSelect?(indexPath.row)
    }
}
