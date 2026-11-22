import UIKit

/// iPad-only chrome helpers: Tools/Profile sheets, column metrics, reading insets.
/// iPhone keeps the classic 4-tab shell — never call sheet presentation paths on phone.
enum PadChrome {
    static var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    /// Notes-like Caderno primary column (~⅓–⅓+ of the window).
    static let notebookPrimaryFraction: CGFloat = 0.35
    static let notebookPrimaryMin: CGFloat = 320
    static let notebookPrimaryMax: CGFloat = 420

    /// Horizontal reading inset inside the note editor on regular-width iPad (~Notes).
    static let editorHorizontalInset: CGFloat = 24

    /// Large form sheet for Tools / Profile on iPad.
    static let utilitySheetSize = CGSize(width: 700, height: 800)

    /// Present Tools or Profile as a large modal sheet with its own navigation stack + Done.
    @MainActor
    static func presentUtilitySheet(
        root: UIViewController,
        from host: UIViewController,
        animated: Bool = true,
        accessibilityId: String? = nil
    ) {
        precondition(isPad, "Utility sheets are iPad-only; iPhone keeps tab roots")
        let nav: UINavigationController
        if let existing = root as? UINavigationController {
            nav = existing
        } else {
            nav = UINavigationController(rootViewController: root)
            KCChrome.style(navigationController: nav)
            nav.navigationBar.prefersLargeTitles = true
        }
        if let id = accessibilityId {
            nav.view.accessibilityIdentifier = id
        }
        installDoneButton(on: nav.viewControllers.first ?? root, nav: nav)

        nav.modalPresentationStyle = .formSheet
        nav.preferredContentSize = utilitySheetSize
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.selectedDetentIdentifier = .large
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
            if #available(iOS 16.0, *) {
                sheet.prefersEdgeAttachedInCompactHeight = true
            }
        }
        host.present(nav, animated: animated)
    }

    @MainActor
    private static func installDoneButton(on root: UIViewController, nav: UINavigationController) {
        // `.plain` + explicit accent tint — `.done` can paint white on warm beige (invisible).
        let done = UIBarButtonItem(
            title: String(localized: "Fechar"),
            style: .plain,
            target: nil,
            action: nil
        )
        done.primaryAction = UIAction { [weak nav] _ in
            nav?.dismiss(animated: true)
        }
        done.tintColor = KCDesign.accent
        done.accessibilityLabel = String(localized: "Fechar")
        done.accessibilityIdentifier = "pad.sheet.done"
        nav.navigationBar.tintColor = KCDesign.accent
        nav.view.tintColor = KCDesign.accent
        // Prefer left so we don't collide with Profile / Tools trailing actions.
        if root.navigationItem.leftBarButtonItem == nil {
            root.navigationItem.leftBarButtonItem = done
        } else {
            root.navigationItem.rightBarButtonItem = done
        }
    }

    /// Bar button that opens Tools (wrench) — used on Caderno / Grupos primary toolbars.
    @MainActor
    static func makeToolsBarButton(target: Any?, action: Selector) -> UIBarButtonItem {
        let item = UIBarButtonItem(
            image: UIImage(systemName: "wrench.and.screwdriver"),
            style: .plain,
            target: target,
            action: action
        )
        item.accessibilityLabel = String(localized: "Ferramentas")
        item.accessibilityIdentifier = "pad.toolbar.tools"
        return item
    }

    /// Bar button that opens Profile.
    @MainActor
    static func makeProfileBarButton(target: Any?, action: Selector) -> UIBarButtonItem {
        let item = UIBarButtonItem(
            image: UIImage(systemName: "person.crop.circle"),
            style: .plain,
            target: target,
            action: action
        )
        item.accessibilityLabel = String(localized: "Perfil")
        item.accessibilityIdentifier = "pad.toolbar.profile"
        return item
    }
}
