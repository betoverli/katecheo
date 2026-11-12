import UIKit

/// Root tabs: Caderno · Grupos · Ferramentas · Perfil.
/// Leitura / Temas / Listas / Livros live under Ferramentas (Tools).
final class NativeRootTabBarController: UITabBarController {
    private var didScheduleSettingsGuide = false

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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionDidChange),
            name: .nativeSessionDidChange,
            object: nil
        )
        refreshActivityDots()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        presentSettingsGuideIfNeeded()
    }

    @objc private func sessionDidChange() {
        presentSettingsGuideIfNeeded(forceSchedule: true)
    }

    /// Once per account/device after sign-in (also for existing TestFlight testers).
    private func presentSettingsGuideIfNeeded(forceSchedule: Bool = false) {
        guard NativeAPIClient.hasBearer else { return }
        guard OnboardingStore.shouldShowSettingsGuide else { return }
        if didScheduleSettingsGuide, !forceSchedule { return }

        // Don't cover an active sign-in sheet — wait until the stack is clear.
        var top: UIViewController = self
        while let presented = top.presentedViewController { top = presented }
        if top is NativeSignInViewController { return }
        if let nav = top as? UINavigationController, nav.viewControllers.first is NativeSignInViewController {
            return
        }
        if top is SettingsGuideViewController { return }

        didScheduleSettingsGuide = true
        // Let sign-in dismiss / first layout settle before presenting.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.presentSettingsGuideNow()
        }
    }

    private func presentSettingsGuideNow() {
        guard NativeAPIClient.hasBearer else { return }
        guard OnboardingStore.shouldShowSettingsGuide else { return }
        var top: UIViewController = self
        while let presented = top.presentedViewController { top = presented }
        if top is SettingsGuideViewController { return }
        if top is NativeSignInViewController { return }

        let guide = SettingsGuideViewController()
        guide.modalPresentationStyle = .fullScreen
        top.present(guide, animated: true)
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
