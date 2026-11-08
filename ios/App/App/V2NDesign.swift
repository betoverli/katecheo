import UIKit

/// Design tokens for Verse2Note native UI.
/// Palette follows the notebook app icon: warm paper, leather spine, blue bookmark.
enum V2NDesign {
    // MARK: - Colors (light / dark)

    /// Warm bronze accent — primary chrome tint (tabs, buttons, nav).
    static let accent = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.83, green: 0.65, blue: 0.45, alpha: 1) // #D4A574
        }
        return UIColor(red: 0.69, green: 0.48, blue: 0.27, alpha: 1) // #B07A45
    }

    /// Soft warm fill for selected chips / subtle highlights.
    static let accentSoft = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.83, green: 0.65, blue: 0.45, alpha: 0.22)
        }
        return UIColor(red: 0.69, green: 0.48, blue: 0.27, alpha: 0.14)
    }

    /// Notebook spine taupe — secondary brand mark (row spine, icons).
    static let spine = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.55, green: 0.50, blue: 0.45, alpha: 1)
        }
        return UIColor(red: 0.675, green: 0.592, blue: 0.518, alpha: 1) // #AC9784
    }

    /// Blue bookmark ribbon — bible refs / secondary actions.
    static let bookmark = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.35, green: 0.65, blue: 0.95, alpha: 1)
        }
        return UIColor(red: 0.188, green: 0.565, blue: 0.910, alpha: 1) // #3090E8
    }

    /// Warm paper canvas (not flat system white).
    static let canvas = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.11, green: 0.10, blue: 0.09, alpha: 1) // #1C1A17
        }
        return UIColor(red: 0.961, green: 0.929, blue: 0.878, alpha: 1) // #F5EDE0
    }

    /// Elevated card / grouped cell surface.
    static let surface = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.18, green: 0.17, blue: 0.15, alpha: 1) // #2E2B26
        }
        return UIColor(red: 0.996, green: 0.988, blue: 0.973, alpha: 1) // #FEFCF8
    }

    /// Grouped table background (slightly cooler than canvas edges).
    static let groupedBackground = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0.09, green: 0.08, blue: 0.07, alpha: 1)
        }
        return UIColor(red: 0.945, green: 0.910, blue: 0.855, alpha: 1) // #F1E8DA
    }

    static let separator = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(white: 1, alpha: 0.10)
        }
        return UIColor(red: 0.675, green: 0.592, blue: 0.518, alpha: 0.28)
    }

    static let danger = UIColor.systemRed

    // MARK: - Typography (Dynamic Type)

    static func displayTitle() -> UIFont {
        preferred(.largeTitle, weight: .bold)
    }

    static func screenTitle() -> UIFont {
        preferred(.title2, weight: .semibold)
    }

    static func sectionHeader() -> UIFont {
        preferred(.footnote, weight: .semibold)
    }

    static func rowTitle() -> UIFont {
        preferred(.body, weight: .semibold)
    }

    static func rowSubtitle() -> UIFont {
        preferred(.subheadline, weight: .regular)
    }

    static func caption() -> UIFont {
        preferred(.caption1, weight: .medium)
    }

    static func body() -> UIFont {
        preferred(.body, weight: .regular)
    }

    static func headline() -> UIFont {
        preferred(.headline, weight: .semibold)
    }

    static func preferred(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style)
        let descriptor = base.fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight],
        ])
        let sized = UIFont(descriptor: descriptor, size: base.pointSize)
        return UIFontMetrics(forTextStyle: style).scaledFont(for: sized)
    }

    // MARK: - Spacing

    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // MARK: - Radii

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 22
        static let pill: CGFloat = 999
    }

    // MARK: - Shadow / material

    static func applyCardShadow(to layer: CALayer) {
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = UITraitCollection.current.userInterfaceStyle == .dark ? 0.35 : 0.08
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 8
        layer.masksToBounds = false
    }

    static func softMaterial() -> UIBlurEffect {
        if V2NGlassMaterial.sdkHasLiquidGlass() {
            // Classic blur still used as fallback surface when glass isn't painted on a view.
            return UIBlurEffect(style: .systemChromeMaterial)
        }
        return UIBlurEffect(style: .systemChromeMaterial)
    }
}

// MARK: - Chrome (nav + tab)

enum V2NChrome {
    /// Apply brand tint + nav/tab appearances once at launch.
    static func applyAppWide() {
        precondition(Thread.isMainThread)
        let accent = V2NDesign.accent
        UIView.appearance().tintColor = accent

        let nav = UINavigationBarAppearance()
        nav.configureWithDefaultBackground()
        if !V2NGlassMaterial.sdkHasLiquidGlass() {
            nav.configureWithOpaqueBackground()
            nav.backgroundColor = V2NDesign.surface.withAlphaComponent(0.94)
        }
        nav.titleTextAttributes = [
            .foregroundColor: UIColor.label,
            .font: V2NDesign.preferred(.headline, weight: .semibold),
        ]
        nav.largeTitleTextAttributes = [
            .foregroundColor: UIColor.label,
            .font: V2NDesign.preferred(.largeTitle, weight: .bold),
        ]
        nav.shadowColor = .clear

        let navProxy = UINavigationBar.appearance()
        navProxy.tintColor = accent
        navProxy.standardAppearance = nav
        navProxy.compactAppearance = nav
        navProxy.scrollEdgeAppearance = nav
        if #available(iOS 15.0, *) {
            navProxy.compactScrollEdgeAppearance = nav
        }

        let tab = UITabBarAppearance()
        tab.configureWithDefaultBackground()
        if !V2NGlassMaterial.sdkHasLiquidGlass() {
            tab.configureWithOpaqueBackground()
            tab.backgroundColor = V2NDesign.surface.withAlphaComponent(0.96)
        }
        tab.shadowColor = .clear
        let tabItem = UITabBarItemAppearance()
        tabItem.normal.iconColor = .secondaryLabel
        tabItem.normal.titleTextAttributes = [
            .foregroundColor: UIColor.secondaryLabel,
            .font: V2NDesign.caption(),
        ]
        tabItem.selected.iconColor = accent
        tabItem.selected.titleTextAttributes = [
            .foregroundColor: accent,
            .font: V2NDesign.caption(),
        ]
        tab.stackedLayoutAppearance = tabItem
        tab.inlineLayoutAppearance = tabItem
        tab.compactInlineLayoutAppearance = tabItem

        let tabProxy = UITabBar.appearance()
        tabProxy.tintColor = accent
        tabProxy.unselectedItemTintColor = .secondaryLabel
        tabProxy.standardAppearance = tab
        if #available(iOS 15.0, *) {
            tabProxy.scrollEdgeAppearance = tab
        }

        UIRefreshControl.appearance().tintColor = accent
        UISearchBar.appearance().tintColor = accent
        UIBarButtonItem.appearance().tintColor = accent
    }

    static func style(navigationController: UINavigationController) {
        navigationController.navigationBar.prefersLargeTitles = true
        navigationController.navigationBar.tintColor = V2NDesign.accent
    }

    static func styleCanvas(_ view: UIView) {
        view.backgroundColor = V2NDesign.canvas
    }

    static func styleGroupedTable(_ table: UITableView) {
        table.backgroundColor = V2NDesign.groupedBackground
        table.separatorColor = V2NDesign.separator
        table.sectionHeaderTopPadding = V2NDesign.Space.sm
    }
}

// MARK: - Floating tab bar scroll clearance (TF214)

enum V2NScrollChrome {
    /// Extra bottom inset so scroll content clears a floating / Liquid Glass tab bar.
    /// Pure helper — unit-tested with synthetic metrics.
    static func tabBarClearance(
        tabBarHeight: CGFloat,
        safeAreaBottom: CGFloat,
        tabBarMinYInView: CGFloat?,
        viewHeight: CGFloat
    ) -> CGFloat {
        guard tabBarHeight > 0 else { return 0 }
        var clearance = max(0, tabBarHeight - safeAreaBottom)
        if let minY = tabBarMinYInView {
            let overlap = max(0, viewHeight - max(minY, 0) - safeAreaBottom)
            clearance = max(clearance, overlap)
        }
        if clearance > 0 {
            clearance += V2NDesign.Space.md
        }
        return clearance
    }

    /// Apply `contentInset` / indicator insets so the last rows sit above the tab bar.
    @MainActor
    static func applyTabBarClearance(to scrollView: UIScrollView, from host: UIViewController) {
        let tabBar = host.tabBarController?.tabBar
        let tabHeight = (tabBar?.isHidden == false) ? (tabBar?.bounds.height ?? 0) : 0
        let minY: CGFloat? = {
            guard let tabBar, tabBar.isHidden == false, let hostView = host.view else { return nil }
            return tabBar.convert(tabBar.bounds, to: hostView).minY
        }()
        let clearance = tabBarClearance(
            tabBarHeight: tabHeight,
            safeAreaBottom: host.view?.safeAreaInsets.bottom ?? 0,
            tabBarMinYInView: minY,
            viewHeight: host.view?.bounds.height ?? 0
        )
        // Raise contentInset.bottom only for the portion not already covered by safe-area adjustment.
        let currentBottom = scrollView.contentInset.bottom
        let systemBottom = scrollView.adjustedContentInset.bottom - scrollView.contentInset.bottom
        let needed = max(0, clearance - systemBottom)
        if abs(currentBottom - needed) > 0.5 {
            scrollView.contentInset.bottom = needed
            scrollView.verticalScrollIndicatorInsets.bottom = needed
        }
    }
}

extension UIViewController {
    /// Call from `viewDidLayoutSubviews` on Profile / settings screens that sit above the tab bar.
    @MainActor
    func v2nApplyTabBarScrollClearance(to scrollView: UIScrollView?) {
        guard let scrollView else { return }
        V2NScrollChrome.applyTabBarClearance(to: scrollView, from: self)
    }
}

// MARK: - Haptics

enum V2NHaptics {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
