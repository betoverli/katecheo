import UIKit

/// Root tabs.
/// - iPhone: Caderno · Grupos · Ferramentas · Perfil (unchanged push tabs).
/// - iPadOS 18+ regular width: Caderno · Grupos stay as destinations; Ferramentas /
///   Perfil open as formSheet panels (Caderno/Grupos stay visible behind). Compact
///   iPad (Split View) keeps normal tabs.
/// - iPad iOS 15–17: `PadLegacySidebarShell` is the window root instead (see AppRoot).
final class NativeRootTabBarController: UITabBarController, UITabBarControllerDelegate {
    private var didScheduleSettingsGuide = false
    /// Apply default sidebar visibility once per process (don't fight mid-session toggles).
    private var didApplyDefaultTabSidebarVisibility = false

    /// XCUITest opt-in: expand the production tabSidebar (tiled) so landscape honesty
    /// tests can tap a real hittable list row beside the editor.
    static let expandTabSidebarLaunchArgument = "-katecheoUITestExpandTabSidebar"

    override func viewDidLoad() {
        super.viewDidLoad()
        KCChrome.styleScreen(view)
        delegate = self
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
                    applyTabSidebarAppleDefault()
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
        // Re-assert Apple default once after the window/scene orientation is known.
        if #available(iOS 18.0, *), PadChrome.isPad, mode == .tabSidebar {
            applyDefaultTabSidebarVisibilityIfNeeded(forceExpand: false)
            paintSidebarOpaqueIfNeeded()
        }
        presentSettingsGuideIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if #available(iOS 18.0, *), PadChrome.isPad, mode == .tabSidebar {
            paintSidebarOpaqueIfNeeded()
        }
    }

    /// iPadOS 18+ tabSidebar: tile content beside the sidebar (opaque column — no
    /// ghosting under the system material) with Apple's portrait/landscape visibility.
    @available(iOS 18.0, *)
    func applyTabSidebarAppleDefault() {
        mode = .tabSidebar
        sidebar.preferredLayout = .tile
        view.backgroundColor = KCDesign.screenBackground
        view.accessibilityIdentifier = "pad.shell.tabsidebar"
        applyDefaultTabSidebarVisibilityIfNeeded(forceExpand: false)
        paintSidebarOpaqueIfNeeded()
    }

    /// Screenshot helper: enable tabSidebar + tile even under the XCTest host.
    /// Pass `sidebarHidden` to match Apple's portrait (true) / landscape (false) default.
    @available(iOS 18.0, *)
    func applyTabSidebarForScreenshotsIfNeeded(sidebarHidden: Bool? = nil) {
        mode = .tabSidebar
        sidebar.preferredLayout = .tile
        view.backgroundColor = KCDesign.screenBackground
        view.accessibilityIdentifier = "pad.shell.tabsidebar"
        didApplyDefaultTabSidebarVisibility = true
        if let sidebarHidden {
            sidebar.isHidden = sidebarHidden
        } else {
            sidebar.isHidden = !isLandscapeInterface
        }
        paintSidebarOpaqueIfNeeded()
    }

    @available(iOS 18.0, *)
    private func applyDefaultTabSidebarVisibilityIfNeeded(forceExpand: Bool) {
        guard mode == .tabSidebar, !didApplyDefaultTabSidebarVisibility else { return }
        didApplyDefaultTabSidebarVisibility = true
        sidebar.preferredLayout = .tile
        view.backgroundColor = KCDesign.screenBackground

        let args = ProcessInfo.processInfo.arguments
        let expandForUITest = args.contains(Self.expandTabSidebarLaunchArgument)

        // Most XCUITest launches keep the top tab bar so list rows stay hittable.
        // Opt in with `-katecheoUITestExpandTabSidebar` for production-default honesty.
        if !forceExpand && !expandForUITest {
            let underUITest = args.contains {
                $0.hasPrefix("-katecheoSkip") || $0.hasPrefix("-katecheoUITest")
            }
            if underUITest { return }
        }

        if forceExpand || expandForUITest {
            sidebar.isHidden = false
            paintSidebarOpaqueIfNeeded()
            return
        }

        // Production: Apple default — collapsed in portrait, expanded in landscape.
        sidebar.isHidden = !isLandscapeInterface
        paintSidebarOpaqueIfNeeded()
    }

    /// Make the main-menu sidebar opaque so the Caderno list never ghosts through
    /// when the menu opens as an overlay in portrait.
    @available(iOS 18.0, *)
    func paintSidebarOpaqueIfNeeded() {
        guard mode == .tabSidebar else { return }
        sidebar.preferredLayout = .tile
        view.backgroundColor = KCDesign.screenBackground
        paintSidebarMaterialOpaque(in: view)
    }

    /// Replace translucent sidebar materials with a solid screen background.
    private func paintSidebarMaterialOpaque(in root: UIView) {
        let maxSidebarWidth = max(root.bounds.width * 0.42, 280)
        func walk(_ view: UIView) {
            let looksLikeSidebarChrome = view.frame.width > 40
                && view.frame.width <= maxSidebarWidth
                && view.frame.height > root.bounds.height * 0.5
            if let effect = view as? UIVisualEffectView, looksLikeSidebarChrome || effect.frame.width <= maxSidebarWidth {
                effect.effect = nil
                effect.backgroundColor = KCDesign.screenBackground
                effect.contentView.backgroundColor = KCDesign.screenBackground
                effect.isOpaque = true
            } else if looksLikeSidebarChrome {
                if view.backgroundColor == nil || (view.backgroundColor?.cgColor.alpha ?? 1) < 0.95 {
                    view.backgroundColor = KCDesign.screenBackground
                }
                view.isOpaque = true
            }
            for child in view.subviews {
                walk(child)
            }
        }
        walk(root)
    }

    /// True when the interface is landscape (window scene, else bounds).
    private var isLandscapeInterface: Bool {
        if let scene = view.window?.windowScene {
            switch scene.interfaceOrientation {
            case .landscapeLeft, .landscapeRight:
                return true
            case .portrait, .portraitUpsideDown:
                return false
            case .unknown:
                break
            @unknown default:
                break
            }
        }
        return view.bounds.width > view.bounds.height
    }

    // MARK: - UITabBarControllerDelegate (iPad Tools / Profile sheets)

    func tabBarController(
        _ tabBarController: UITabBarController,
        shouldSelect viewController: UIViewController
    ) -> Bool {
        guard PadChrome.presentsUtilitySheets(for: traitCollection),
              let index = viewControllers?.firstIndex(of: viewController)
        else { return true }
        if index == 2 {
            presentToolsSheet(animated: true)
            return false
        }
        if index == 3 {
            presentProfileSheet(animated: true)
            return false
        }
        return true
    }

    // MARK: - Tools / Profile

    @MainActor
    func presentToolsSheet(
        animated: Bool = true,
        configure: ((VersesHomeViewController) -> Void)? = nil
    ) {
        if !PadChrome.presentsUtilitySheets(for: traitCollection) {
            selectedIndex = 2
            if let nav = selectedViewController as? UINavigationController,
               let home = nav.viewControllers.first as? VersesHomeViewController
            {
                _ = home.view
                configure?(home)
            }
            return
        }
        if let existing = presentedUtilityNav(id: "pad.sheet.tools"),
           let home = existing.viewControllers.first as? VersesHomeViewController
        {
            _ = home.view
            configure?(home)
            return
        }
        dismissUtilitySheetIfNeeded(animated: false)
        let home = VersesHomeViewController()
        let nav = UINavigationController(rootViewController: home)
        KCChrome.style(navigationController: nav)
        nav.navigationBar.prefersLargeTitles = true
        _ = home.view
        configure?(home)
        PadChrome.presentUtilitySheet(
            root: nav,
            from: self,
            animated: animated,
            accessibilityId: "pad.sheet.tools"
        )
    }

    @MainActor
    func presentProfileSheet(
        animated: Bool = true,
        configure: ((ProfileViewController, UINavigationController) -> Void)? = nil
    ) {
        if !PadChrome.presentsUtilitySheets(for: traitCollection) {
            selectedIndex = 3
            if let nav = selectedViewController as? UINavigationController,
               let home = nav.viewControllers.first as? ProfileViewController
            {
                configure?(home, nav)
            }
            return
        }
        if let existing = presentedUtilityNav(id: "pad.sheet.profile"),
           let home = existing.viewControllers.first as? ProfileViewController
        {
            configure?(home, existing)
            return
        }
        dismissUtilitySheetIfNeeded(animated: false)
        let home = ProfileViewController()
        let nav = UINavigationController(rootViewController: home)
        KCChrome.style(navigationController: nav)
        nav.navigationBar.prefersLargeTitles = true
        configure?(home, nav)
        PadChrome.presentUtilitySheet(
            root: nav,
            from: self,
            animated: animated,
            accessibilityId: "pad.sheet.profile"
        )
    }

    private func presentedUtilityNav(id: String) -> UINavigationController? {
        var top: UIViewController = self
        while let presented = top.presentedViewController {
            if let nav = presented as? UINavigationController,
               nav.view.accessibilityIdentifier == id
            {
                return nav
            }
            top = presented
        }
        return nil
    }

    private func dismissUtilitySheetIfNeeded(animated: Bool) {
        if let nav = presentedViewController as? UINavigationController,
           let id = nav.view.accessibilityIdentifier,
           id.hasPrefix("pad.sheet.")
        {
            nav.dismiss(animated: animated)
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
