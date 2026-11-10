import UIKit

/// Root tabs: Caderno · Grupos · Ferramentas · Perfil.
/// Leitura / Temas / Listas / Livros live under Ferramentas (Tools).
final class NativeRootTabBarController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()
        KCChrome.styleScreen(view)
        tabBar.tintColor = KCDesign.accent
        tabBar.unselectedItemTintColor = .secondaryLabel
        tabBar.standardAppearance.backgroundColor = KCDesign.screenBackground
        if #available(iOS 15.0, *) {
            tabBar.scrollEdgeAppearance?.backgroundColor = KCDesign.screenBackground
        }

        let notebook = UINavigationController(rootViewController: NotebookListViewController())
        KCChrome.style(navigationController: notebook)
        notebook.tabBarItem = UITabBarItem(
            title: String(localized: "Caderno"),
            image: UIImage(systemName: "note.text"),
            selectedImage: UIImage(systemName: "note.text")
        )
        notebook.tabBarItem.accessibilityLabel = String(localized: "Caderno")
        notebook.tabBarItem.tag = 0

        let groups = UINavigationController(rootViewController: GroupsListViewController())
        KCChrome.style(navigationController: groups)
        groups.tabBarItem = UITabBarItem(
            title: String(localized: "Grupos"),
            image: UIImage(systemName: "person.2"),
            tag: 1
        )
        groups.tabBarItem.accessibilityLabel = String(localized: "Grupos")

        let tools = UINavigationController(rootViewController: VersesHomeViewController())
        KCChrome.style(navigationController: tools)
        tools.tabBarItem = UITabBarItem(
            title: String(localized: "Ferramentas"),
            image: UIImage(systemName: "wrench.and.screwdriver"),
            tag: 2
        )
        tools.tabBarItem.accessibilityLabel = String(localized: "Ferramentas")

        let profile = UINavigationController(rootViewController: ProfileViewController())
        KCChrome.style(navigationController: profile)
        profile.tabBarItem = UITabBarItem(
            title: String(localized: "Perfil"),
            image: UIImage(systemName: "person"),
            tag: 3
        )
        profile.tabBarItem.accessibilityLabel = String(localized: "Perfil")

        // Default selected: Caderno (Notebook).
        viewControllers = [notebook, groups, tools, profile]
        selectedIndex = 0

        // Liquid Glass paints system chrome on iOS 26; older OS keeps classic appearances from KCChrome.
        _ = KCGlassMaterial.sdkHasLiquidGlass()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshActivityDots),
            name: KCActivityStore.didChangeNotification,
            object: nil
        )
        refreshActivityDots()
    }

    @objc private func refreshActivityDots() {
        applyDot(at: 0, on: KCActivityStore.notebookDot, label: String(localized: "Caderno com itens não lidos"))
        applyDot(at: 1, on: KCActivityStore.groupsDot, label: String(localized: "Grupos com atividade não lida"))
        applyDot(at: 2, on: KCActivityStore.toolsDot, label: String(localized: "Ferramentas com leitura pendente"))
        applyDot(at: 3, on: KCActivityStore.profileDot, label: String(localized: "Perfil com pedidos de amizade"))
    }

    private func applyDot(at index: Int, on: Bool, label: String) {
        guard let item = viewControllers?[index].tabBarItem else { return }
        // Empty badgeValue renders a subtle system red dot (no count).
        item.badgeValue = on ? "" : nil
        item.badgeColor = KCDesign.accent
        if on {
            item.accessibilityValue = label
        } else {
            item.accessibilityValue = nil
        }
    }
}
