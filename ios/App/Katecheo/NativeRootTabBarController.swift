import UIKit

/// Root tabs.
/// - iPhone: Caderno · Grupos · Ferramentas · Perfil (unchanged).
/// - iPad: Caderno · Grupos only; Tools/Profile open as large form sheets.
final class NativeRootTabBarController: UITabBarController {
    private var didScheduleSettingsGuide = false
    private weak var presentedToolsNav: UINavigationController?
    private weak var presentedProfileNav: UINavigationController?
    private weak var toolsHome: VersesHomeViewController?
    private weak var profileHome: ProfileViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        KCChrome.styleScreen(view)
        tabBar.tintColor = KCDesign.accent
        tabBar.unselectedItemTintColor = .secondaryLabel
        tabBar.standardAppearance.backgroundColor = KCDesign.screenBackground
        if #available(iOS 15.0, *) {
            tabBar.scrollEdgeAppearance?.backgroundColor = KCDesign.screenBackground
        }

        // Caderno: iPhone = pre-#131 UINavigationController; iPad = Notes-style split.
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

        if PadChrome.isPad {
            // Tools + Profile are sheets on iPad — only Caderno / Grupos in the tab bar.
            viewControllers = [notebook, groups]
        } else {
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

            viewControllers = [notebook, groups, tools, profile]
        }
        selectedIndex = 0
        // UITest-only: land on Grupos without tapping the floating tab bar.
        if UITestSeed.preferGruposTab {
            selectedIndex = 1
        }

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

    // MARK: - iPad Tools / Profile sheets

    /// Present Ferramentas as a large form sheet (iPad). No-op path for phone tabs.
    @MainActor
    func presentToolsSheet(
        animated: Bool = true,
        configure: ((VersesHomeViewController) -> Void)? = nil
    ) {
        if !PadChrome.isPad {
            selectedIndex = 2
            if let nav = selectedViewController as? UINavigationController,
               let home = nav.viewControllers.first as? VersesHomeViewController
            {
                _ = home.view
                configure?(home)
            }
            return
        }
        if let existing = presentedToolsNav, presentedViewController === existing,
           let home = toolsHome
        {
            configure?(home)
            return
        }
        let home = VersesHomeViewController()
        toolsHome = home
        _ = home.view
        configure?(home)
        presentUtilityAfterClearing(root: home, animated: animated, accessibilityId: "pad.sheet.tools") { [weak self] nav in
            self?.presentedToolsNav = nav
            self?.presentedProfileNav = nil
        }
    }

    /// Present Perfil as a large form sheet (iPad).
    @MainActor
    func presentProfileSheet(
        animated: Bool = true,
        configure: ((ProfileViewController, UINavigationController) -> Void)? = nil
    ) {
        if !PadChrome.isPad {
            selectedIndex = 3
            if let nav = selectedViewController as? UINavigationController,
               let home = nav.viewControllers.first as? ProfileViewController
            {
                configure?(home, nav)
            }
            return
        }
        if let existing = presentedProfileNav, presentedViewController === existing,
           let home = profileHome
        {
            configure?(home, existing)
            return
        }
        let home = ProfileViewController()
        profileHome = home
        // Force view load so header/table paint before the sheet snapshot / first frame.
        _ = home.view
        presentUtilityAfterClearing(root: home, animated: animated, accessibilityId: "pad.sheet.profile") { [weak self] nav in
            self?.presentedProfileNav = nav
            self?.presentedToolsNav = nil
            configure?(home, nav)
        }
    }

    /// Dismiss any existing sheet fully before presenting — UIKit keeps the old
    /// `presentedViewController` until the dismiss completion runs, so a back-to-back
    /// Tools→Profile present otherwise leaves `pad.sheet.tools` on screen.
    @MainActor
    private func presentUtilityAfterClearing(
        root: UIViewController,
        animated: Bool,
        accessibilityId: String,
        onPresented: @escaping (UINavigationController) -> Void
    ) {
        let present = { [weak self] in
            guard let self else { return }
            PadChrome.presentUtilitySheet(
                root: root,
                from: self,
                animated: animated,
                accessibilityId: accessibilityId
            )
            if let nav = self.presentedViewController as? UINavigationController {
                onPresented(nav)
            }
        }
        if presentedViewController != nil {
            dismiss(animated: false, completion: present)
        } else {
            present()
        }
    }

    @MainActor
    private func topMostPresenter() -> UIViewController {
        var top: UIViewController = self
        while let presented = top.presentedViewController { top = presented }
        return top
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
        if !PadChrome.isPad {
            applyDot(at: 2, on: KCActivityStore.toolsDot, label: String(localized: "Ferramentas com leitura pendente"))
            applyDot(at: 3, on: KCActivityStore.profileDot, label: String(localized: "Perfil com pedidos de amizade"))
        }
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
