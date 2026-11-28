import UIKit

/// iPad-only chrome helpers: column metrics, reading insets, split tiling, utility sheets.
/// iPhone keeps the classic 4-tab shell.
enum PadChrome {
    static var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    /// Notes-folder list column — kept modest so portrait + tabSidebar still tiles.
    static let notebookPrimaryFraction: CGFloat = 0.28
    static let notebookPrimaryMin: CGFloat = 220
    static let notebookPrimaryMax: CGFloat = 320

    /// Horizontal text-container inset on regular-width iPad (Notes-like leading margin).
    /// Editor pins to the column leading edge — not a centered readable column.
    static let editorHorizontalInset: CGFloat = 20

    /// Pre-#136 iPhone / compact text-container inset (`KCDesign.Space.md`).
    static let phoneEditorHorizontalInset: CGFloat = 16

    /// Cap line length only on very wide Stage Manager windows; keep leading alignment.
    static let editorMaxReadableWidth: CGFloat = 720

    /// Large form sheet size (Profile / Tools) — App Store account–like panel.
    static let utilitySheetSize = CGSize(width: 540, height: 720)

    /// True when Tools/Profile should open as a modal panel (regular-width iPad).
    static func presentsUtilitySheets(for traits: UITraitCollection) -> Bool {
        isPad && traits.horizontalSizeClass == .regular
    }

    /// Apply Notes-folder split chrome: beside (tile), never overlay the detail.
    /// Assignments are idempotent — re-setting the same preferred* values every
    /// layout pass can keep UIKit invalidating layout (XCTest hang).
    @MainActor
    static func applyNotesFolderSplitChrome(
        to split: UISplitViewController,
        primaryFraction: CGFloat = notebookPrimaryFraction,
        min: CGFloat = notebookPrimaryMin,
        max: CGFloat = notebookPrimaryMax
    ) {
        if #available(iOS 16.0, *) {
            // Tile displaces columns; `.overlay` hid note text under the list (TF 499).
            if split.preferredSplitBehavior != .tile {
                split.preferredSplitBehavior = .tile
            }
        }
        if split.preferredDisplayMode != .oneBesideSecondary {
            split.preferredDisplayMode = .oneBesideSecondary
        }
        if !split.presentsWithGesture {
            split.presentsWithGesture = true
        }
        if #available(iOS 14.5, *) {
            if split.displayModeButtonVisibility != .never {
                split.displayModeButtonVisibility = .never
            }
        }
        if abs(split.preferredPrimaryColumnWidthFraction - primaryFraction) > 0.0001 {
            split.preferredPrimaryColumnWidthFraction = primaryFraction
        }
        if split.minimumPrimaryColumnWidth != min {
            split.minimumPrimaryColumnWidth = min
        }
        if split.maximumPrimaryColumnWidth != max {
            split.maximumPrimaryColumnWidth = max
        }
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
        // Re-apply only the deltas — avoid layout thrash inside viewDidLayoutSubviews.
        applyNotesFolderSplitChrome(to: split)
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

    /// Clear any leftover secondary leading safe-area inset.
    ///
    /// A previous inset-by-overlap hack double-counted when UIKit already tiled
    /// the columns (child VC `convert` often reports secondary at x=0 even while
    /// beside). Tiling is owned by `.tile` + `.oneBesideSecondary`; do **not**
    /// invent leading insets from those unreliable frames.
    @MainActor
    static func ensureSecondaryContentClearsPrimary(on split: UISplitViewController) {
        guard let secondary = split.viewController(for: .secondary) else { return }
        if secondary.additionalSafeAreaInsets.left != 0 {
            secondary.additionalSafeAreaInsets.left = 0
        }
    }

    /// Leading edge of the detail column in window coordinates when tiled.
    /// Prefers a secondary VC frame that already sits beside the primary; otherwise
    /// uses the primary's trailing edge (child VC frames can falsely report x=0).
    @MainActor
    static func secondaryLeadingEdge(in split: UISplitViewController) -> CGFloat? {
        guard let primary = columnWindowFrame(for: .primary, in: split) else { return nil }
        if let secondary = columnWindowFrame(for: .secondary, in: split),
           secondary.minX >= primary.maxX - 2
        {
            return secondary.minX
        }
        return primary.maxX
    }

    /// Present Tools or Profile as a large modal sheet (regular-width iPad).
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
        var top = host
        while let presented = top.presentedViewController { top = presented }
        top.present(nav, animated: animated)
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
