import UIKit

/// iPad-only chrome helpers: column metrics, reading insets, split tiling.
/// iPhone keeps the classic 4-tab shell.
enum PadChrome {
    static var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    /// Notes-folder list column — sized so portrait + main-menu sidebar still tiles
    /// (never overlays) the note detail.
    static let notebookPrimaryFraction: CGFloat = 0.32
    static let notebookPrimaryMin: CGFloat = 260
    static let notebookPrimaryMax: CGFloat = 380

    /// Horizontal reading inset inside the note editor on regular-width iPad (~Notes).
    static let editorHorizontalInset: CGFloat = 24

    /// Large form sheet size (deep-link / modal fallback only).
    static let utilitySheetSize = CGSize(width: 700, height: 800)

    /// Apply Notes-folder split chrome: beside (tile), never overlay the detail.
    @MainActor
    static func applyNotesFolderSplitChrome(
        to split: UISplitViewController,
        primaryFraction: CGFloat = notebookPrimaryFraction,
        min: CGFloat = notebookPrimaryMin,
        max: CGFloat = notebookPrimaryMax
    ) {
        split.preferredDisplayMode = .oneBesideSecondary
        split.presentsWithGesture = true
        if #available(iOS 14.5, *) {
            split.displayModeButtonVisibility = .never
        }
        if #available(iOS 16.0, *) {
            // Tile displaces columns; `.overlay` hid note text under the list (TF 499).
            split.preferredSplitBehavior = .tile
        }
        split.preferredPrimaryColumnWidthFraction = primaryFraction
        split.minimumPrimaryColumnWidth = min
        split.maximumPrimaryColumnWidth = max
    }

    /// If UIKit flips into overlay/over-secondary, snap back to beside.
    /// Only when the host is wide enough for two columns — setting
    /// `preferredDisplayMode` in a narrow XCTest window (e.g. 390pt) while
    /// UIKit keeps overlay causes an infinite layout loop / hang.
    @MainActor
    static func enforceBesideDisplayMode(on split: UISplitViewController) {
        guard !split.isCollapsed else { return }
        let minWidthForTile = notebookPrimaryMin + 320
        guard split.view.bounds.width >= minWidthForTile else { return }
        switch split.displayMode {
        case .oneOverSecondary, .primaryOverlay:
            if split.preferredDisplayMode != .oneBesideSecondary {
                split.preferredDisplayMode = .oneBesideSecondary
            }
        default:
            break
        }
    }

    /// Present a utility screen as a large modal sheet (rare fallback).
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
        let done = UIBarButtonItem(
            title: String(localized: "Fechar"),
            style: .done,
            target: nil,
            action: nil
        )
        done.primaryAction = UIAction { [weak nav] _ in
            nav?.dismiss(animated: true)
        }
        done.accessibilityLabel = String(localized: "Fechar")
        done.accessibilityIdentifier = "pad.sheet.done"
        if root.navigationItem.leftBarButtonItem == nil {
            root.navigationItem.leftBarButtonItem = done
        } else {
            root.navigationItem.rightBarButtonItem = done
        }
    }
}
