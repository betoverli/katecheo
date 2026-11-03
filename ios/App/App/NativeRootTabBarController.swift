import UIKit

/// Phase 5 root: native Caderno + Grupos + Perfil + Versículos; Leitura still placeholder (no Cap host).
final class NativeRootTabBarController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()
        V2NChrome.styleCanvas(view)
        tabBar.tintColor = V2NDesign.accent

        let notebook = UINavigationController(rootViewController: NotebookListViewController())
        V2NChrome.style(navigationController: notebook)
        notebook.tabBarItem = UITabBarItem(
            title: "Caderno",
            image: UIImage(systemName: "note.text"),
            selectedImage: UIImage(systemName: "note.text")
        )
        notebook.tabBarItem.accessibilityLabel = "Caderno"

        let verses = UINavigationController(rootViewController: VersesHomeViewController())
        V2NChrome.style(navigationController: verses)
        verses.tabBarItem = UITabBarItem(title: "Versículos", image: UIImage(systemName: "book"), tag: 1)
        verses.tabBarItem.accessibilityLabel = "Versículos"

        let groups = UINavigationController(rootViewController: GroupsListViewController())
        V2NChrome.style(navigationController: groups)
        groups.tabBarItem = UITabBarItem(title: "Grupos", image: UIImage(systemName: "person.2"), tag: 2)
        groups.tabBarItem.accessibilityLabel = "Grupos"

        let reading = UINavigationController(
            rootViewController: ComingSoonTabViewController(
                titleText: "Leitura",
                systemImage: "calendar",
                detailText: "Planos de leitura em breve nativo.\nOs outros separadores já estão no app."
            )
        )
        V2NChrome.style(navigationController: reading)
        reading.tabBarItem = UITabBarItem(title: "Leitura", image: UIImage(systemName: "calendar"), tag: 3)
        reading.tabBarItem.accessibilityLabel = "Leitura"

        let profile = UINavigationController(rootViewController: ProfileViewController())
        V2NChrome.style(navigationController: profile)
        profile.tabBarItem = UITabBarItem(title: "Perfil", image: UIImage(systemName: "person"), tag: 4)
        profile.tabBarItem.accessibilityLabel = "Perfil"

        viewControllers = [verses, groups, notebook, reading, profile]
        selectedIndex = 2

        // Liquid Glass paints system chrome on iOS 26; older OS keeps classic appearances from V2NChrome.
        _ = V2NGlassMaterial.sdkHasLiquidGlass()
    }
}
