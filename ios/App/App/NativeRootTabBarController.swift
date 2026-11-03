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
            title: String(localized: "Caderno"),
            image: UIImage(systemName: "note.text"),
            selectedImage: UIImage(systemName: "note.text")
        )
        notebook.tabBarItem.accessibilityLabel = String(localized: "Caderno")

        let verses = UINavigationController(rootViewController: VersesHomeViewController())
        V2NChrome.style(navigationController: verses)
        verses.tabBarItem = UITabBarItem(title: String(localized: "Versículos"), image: UIImage(systemName: "book"), tag: 1)
        verses.tabBarItem.accessibilityLabel = String(localized: "Versículos")

        let groups = UINavigationController(rootViewController: GroupsListViewController())
        V2NChrome.style(navigationController: groups)
        groups.tabBarItem = UITabBarItem(title: String(localized: "Grupos"), image: UIImage(systemName: "person.2"), tag: 2)
        groups.tabBarItem.accessibilityLabel = String(localized: "Grupos")

        let reading = UINavigationController(
            rootViewController: ComingSoonTabViewController(
                titleText: String(localized: "Leitura"),
                systemImage: "calendar",
                detailText: String(localized: "Planos de leitura em breve nativo.\nOs outros separadores já estão no app.")
            )
        )
        V2NChrome.style(navigationController: reading)
        reading.tabBarItem = UITabBarItem(title: String(localized: "Leitura"), image: UIImage(systemName: "calendar"), tag: 3)
        reading.tabBarItem.accessibilityLabel = String(localized: "Leitura")

        let profile = UINavigationController(rootViewController: ProfileViewController())
        V2NChrome.style(navigationController: profile)
        profile.tabBarItem = UITabBarItem(title: String(localized: "Perfil"), image: UIImage(systemName: "person"), tag: 4)
        profile.tabBarItem.accessibilityLabel = String(localized: "Perfil")

        viewControllers = [verses, groups, notebook, reading, profile]
        selectedIndex = 2

        // Liquid Glass paints system chrome on iOS 26; older OS keeps classic appearances from V2NChrome.
        _ = V2NGlassMaterial.sdkHasLiquidGlass()
    }
}
