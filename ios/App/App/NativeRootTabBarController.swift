import UIKit

/// Root tabs: Caderno · Grupos · Ferramentas · Perfil.
/// Leitura / Temas / Listas / Livros live under Ferramentas (Tools).
final class NativeRootTabBarController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()
        V2NChrome.styleCanvas(view)
        tabBar.tintColor = V2NDesign.accent

        let notebook = UINavigationController(rootViewController: NotebookListViewController())
        V2NChrome.style(navigationController: notebook)
        notebook.tabBarItem = UITabBarItem(
            title: String(localized: "Caderno"),
            image: UIImage(systemName: "note.text"),
            selectedImage: UIImage(systemName: "note.text")
        )
        notebook.tabBarItem.accessibilityLabel = String(localized: "Caderno")
        notebook.tabBarItem.tag = 0

        let groups = UINavigationController(rootViewController: GroupsListViewController())
        V2NChrome.style(navigationController: groups)
        groups.tabBarItem = UITabBarItem(
            title: String(localized: "Grupos"),
            image: UIImage(systemName: "person.2"),
            tag: 1
        )
        groups.tabBarItem.accessibilityLabel = String(localized: "Grupos")

        let tools = UINavigationController(rootViewController: VersesHomeViewController())
        V2NChrome.style(navigationController: tools)
        tools.tabBarItem = UITabBarItem(
            title: String(localized: "Ferramentas"),
            image: UIImage(systemName: "wrench.and.screwdriver"),
            tag: 2
        )
        tools.tabBarItem.accessibilityLabel = String(localized: "Ferramentas")

        let profile = UINavigationController(rootViewController: ProfileViewController())
        V2NChrome.style(navigationController: profile)
        profile.tabBarItem = UITabBarItem(
            title: String(localized: "Perfil"),
            image: UIImage(systemName: "person"),
            tag: 3
        )
        profile.tabBarItem.accessibilityLabel = String(localized: "Perfil")

        // Default selected: Caderno (Notebook).
        viewControllers = [notebook, groups, tools, profile]
        selectedIndex = 0

        // Liquid Glass paints system chrome on iOS 26; older OS keeps classic appearances from V2NChrome.
        _ = V2NGlassMaterial.sdkHasLiquidGlass()
    }
}
