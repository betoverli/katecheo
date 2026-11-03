import UIKit

/// Phase 5 root: native Caderno + Grupos + Perfil + Versículos; Leitura still placeholder (no Cap host).
final class NativeRootTabBarController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let notebook = UINavigationController(rootViewController: NotebookListViewController())
        notebook.tabBarItem = UITabBarItem(
            title: "Caderno",
            image: UIImage(systemName: "note.text"),
            selectedImage: UIImage(systemName: "note.text")
        )

        let verses = UINavigationController(rootViewController: VersesHomeViewController())
        verses.tabBarItem = UITabBarItem(title: "Versículos", image: UIImage(systemName: "book"), tag: 1)

        let groups = UINavigationController(rootViewController: GroupsListViewController())
        groups.tabBarItem = UITabBarItem(title: "Grupos", image: UIImage(systemName: "person.2"), tag: 2)

        let reading = UINavigationController(
            rootViewController: ComingSoonTabViewController(
                titleText: "Leitura",
                systemImage: "calendar",
                detailText: "Planos de leitura em breve nativo.\nOs outros separadores já estão no app."
            )
        )
        reading.tabBarItem = UITabBarItem(title: "Leitura", image: UIImage(systemName: "calendar"), tag: 3)

        let profile = UINavigationController(rootViewController: ProfileViewController())
        profile.tabBarItem = UITabBarItem(title: "Perfil", image: UIImage(systemName: "person"), tag: 4)

        viewControllers = [verses, groups, notebook, reading, profile]
        selectedIndex = 2
    }
}
