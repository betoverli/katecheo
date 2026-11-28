import UIKit

/// Root tabs.
/// - iPhone: Caderno · Grupos · Ferramentas · Perfil (unchanged).
/// - iPadOS 18+: same four destinations with `mode = .tabSidebar` (user can toggle
///   sidebar vs top tab bar; system persists the choice).
/// - iPad iOS 15–17: `PadLegacySidebarShell` is the window root instead (see AppRoot).
final class NativeRootTabBarController: UITabBarController {
    private var didScheduleSettingsGuide = false
    /// Apply default sidebar-expanded once per process (don't fight mid-session toggles).
    private var didApplyDefaultTabSidebarVisibility = false

    override func viewDidLoad() {
        super.viewDidLoad()
        KCChrome.styleScreen(view)
        tabBar.tintColor = KCDesign.accent
        tabBar.unselectedItemTintColor = .secondaryLabel
        tabBar.standardAppearance.backgroundColor = KCDesign.screenBackground
        if #available(iOS 15.0, *) {
            tabBar.scrollEdgeAppearance?.backgroundColor = KCDesign.screenBackground
        }

        let notebook = NotebookChrome.makeTabRoot()
        notebook.tabBarItem = UITabBarItem(
            title: String(localized: "Caderno"),
            image: UIImage(systemName: "note.text"),
            selectedImage: UIImage(systemName: "note.text")
        )
        notebook.tabBarItem.accessibilityLabel = String(localized: "Caderno")
        notebook.tabBarItem.accessibilityIdentifier = "tab.caderno"
        notebook.tabBarItem.tag = 0

        let groups = GroupsChrome.makeTabRoot()
        groups.tabBarItem = UITabBarItem(
            title: String(localized: "Grupos"),
            image: UIImage(systemName: "person.2"),
            tag: 1
        )
        groups.tabBarItem.accessibilityLabel = String(localized: "Grupos")
        groups.tabBarItem.accessibilityIdentifier = "tab.grupos"

        let tools = UINavigationController(rootViewController: VersesHomeViewController())
        KCChrome.style(navigationController: tools)
        tools.tabBarItem = UITabBarItem(
            title: String(localized: "Ferramentas"),
            image: UIImage(systemName: "wrench.and.screwdriver"),
            tag: 2
        )
        tools.tabBarItem.accessibilityLabel = String(localized: "Ferramentas")
        tools.tabBarItem.accessibilityIdentifier = "tab.ferramentas"

        let profile = UINavigationController(rootViewController: ProfileViewController())
        KCChrome.style(navigationController: profile)
        profile.tabBarItem = UITabBarItem(
            title: String(localized: "Perfil"),
            image: UIImage(systemName: "person"),
            tag: 3
        )
        profile.tabBarItem.accessibilityLabel = String(localized: "Perfil")
        profile.tabBarItem.accessibilityIdentifier = "tab.perfil"

        viewControllers = [notebook, groups, tools, profile]
        selectedIndex = 0
        if UITestSeed.preferGruposTab {
            selectedIndex = 1
        }

        if PadChrome.isPad {
            // iPadOS 18+: system sidebar ↔ top tab bar (user toggle, system-persisted).
            // Skip under XCTest host windows — `mode = .tabSidebar` + drawHierarchy
            // (afterScreenUpdates) hangs the iPad unit-test runner. The real app (XCUITest
            // launch / TestFlight) still gets tabSidebar via AppRoot → this controller.
            // Screenshot tests may opt in via `applyTabSidebarForScreenshotsIfNeeded()`.
            if #available(iOS 18.0, *) {
                let underXCTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
                if !underXCTest {
                    applyTabSidebarDefaultExpanded()
                } else {
                    view.accessibilityIdentifier = "pad.shell.tabs"
                }
            }
        }

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
        // System defaults to hiding the sidebar in portrait — re-assert expanded once.
        if #available(iOS 18.0, *), PadChrome.isPad, mode == .tabSidebar {
            applyDefaultTabSidebarVisibilityIfNeeded()
        }
        presentSettingsGuideIfNeeded()
    }

    /// iPadOS 18+ tabSidebar with the main-menu sidebar visible by default.
    @available(iOS 18.0, *)
    func applyTabSidebarDefaultExpanded() {
        mode = .tabSidebar
        view.accessibilityIdentifier = "pad.shell.tabsidebar"
        applyDefaultTabSidebarVisibilityIfNeeded()
    }

    /// Screenshot / test helper: enable tabSidebar even under the XCTest host.
    @available(iOS 18.0, *)
    func applyTabSidebarForScreenshotsIfNeeded() {
        applyTabSidebarDefaultExpanded()
    }

    @available(iOS 18.0, *)
    private func applyDefaultTabSidebarVisibilityIfNeeded() {
        guard mode == .tabSidebar, !didApplyDefaultTabSidebarVisibility else { return }
        // Expand the left main-menu column; user can still toggle to the top tab bar.
        sidebar.isHidden = false
        didApplyDefaultTabSidebarVisibility = true
    }

    // MARK: - Tools / Profile (tabs on iPad + iPhone; deep-link API)

    @MainActor
    func presentToolsSheet(
        animated: Bool = true,
        configure: ((VersesHomeViewController) -> Void)? = nil
    ) {
        selectedIndex = 2
        if let nav = selectedViewController as? UINavigationController,
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
        if let nav = selectedViewController as? UINavigationController,
           let home = nav.viewControllers.first as? ProfileViewController
        {
            configure?(home, nav)
        }
    }

    @objc private func sessionDidChange() {
        presentSettingsGuideIfNeeded(forceSchedule: true)
    }

    private func presentSettingsGuideIfNeeded(forceSchedule: Bool = false) {
        guard NativeAPIClient.hasBearer else { return }
        guard OnboardingStore.shouldShowSettingsGuide else { return }
        if didScheduleSettingsGuide, !forceSchedule { return }

        var top: UIViewController = self
        while let presented = top.presentedViewController { top = presented }
        if top is NativeSignInViewController { return }
        if let nav = top as? UINavigationController, nav.viewControllers.first is NativeSignInViewController {
            return
        }
        if top is SettingsGuideViewController { return }

        didScheduleSettingsGuide = true
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
        item.badgeValue = on ? "" : nil
        item.badgeColor = KCDesign.accent
        item.accessibilityValue = on ? label : nil
    }
}
