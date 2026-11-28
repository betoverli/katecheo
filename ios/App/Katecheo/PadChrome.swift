import UIKit

/// iPad-only chrome helpers: column metrics, reading insets, split tiling.
/// iPhone keeps the classic 4-tab shell.
enum PadChrome {
    static var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    /// Notes-folder list column — kept modest so portrait + tabSidebar still tiles.
    static let notebookPrimaryFraction: CGFloat = 0.28
    static let notebookPrimaryMin: CGFloat = 220
    static let notebookPrimaryMax: CGFloat = 320

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
        if #available(iOS 16.0, *) {
            // Tile displaces columns; `.overlay` hid note text under the list (TF 499).
            split.preferredSplitBehavior = .tile
        }
        split.preferredDisplayMode = .oneBesideSecondary
        split.presentsWithGesture = true
        if #available(iOS 14.5, *) {
            split.displayModeButtonVisibility = .never
        }
        split.preferredPrimaryColumnWidthFraction = primaryFraction
        split.minimumPrimaryColumnWidth = min
        split.maximumPrimaryColumnWidth = max
        // Only force-show primary when UIKit hid it (`.secondaryOnly`). Calling
        // `show(.primary)` on every detail swap can re-layout panels full-bleed.
        if !split.isCollapsed, split.view.window != nil, split.displayMode == .secondaryOnly {
            split.show(.primary)
        }
    }

    /// If UIKit flips into overlay / secondary-only, snap back to beside.
    /// Only when the host is wide enough for two columns — setting
    /// `preferredDisplayMode` in a narrow XCTest window (e.g. 390pt) while
    /// UIKit keeps overlay causes an infinite layout loop / hang.
    @MainActor
    static func enforceBesideDisplayMode(on split: UISplitViewController) {
        guard !split.isCollapsed else { return }
        let minWidthForTile = notebookPrimaryMin + 280
        guard split.view.bounds.width >= minWidthForTile else { return }
        let broken: Bool
        switch split.displayMode {
        case .oneOverSecondary, .primaryOverlay, .secondaryOnly:
            broken = true
        default:
            broken = false
        }
        guard broken else { return }
        if #available(iOS 16.0, *) {
            if split.preferredSplitBehavior != .tile {
                split.preferredSplitBehavior = .tile
            }
        }
        if split.preferredDisplayMode != .oneBesideSecondary {
            split.preferredDisplayMode = .oneBesideSecondary
        }
        if split.displayMode == .secondaryOnly {
            split.show(.primary)
        }
    }

    /// Real on-screen frame of a split column VC's view in window coordinates.
    /// Uses `convert(_:to: nil)` only — never `primaryColumnWidth` or a custom
    /// `accessibilityFrame`.
    @MainActor
    static func columnWindowFrame(
        for column: UISplitViewController.Column,
        in split: UISplitViewController
    ) -> CGRect? {
        guard let columnView = split.viewController(for: column)?.view, columnView.window != nil else {
            return nil
        }
        return columnView.convert(columnView.bounds, to: nil)
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
