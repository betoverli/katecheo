import UIKit

/// Native bottom confirmations (UIKit action sheet ≈ SwiftUI `.confirmationDialog`).
///
/// On iPhone (compact width), never configure `popoverPresentationController`.
/// Setting `sourceView` / `barButtonItem` there makes recent iOS versions draw a
/// floating balloon over the navigation title instead of the bottom sheet
/// (Profile Sign out, Friends accept/decline, etc.).
///
/// On iPad (regular width), anchor to a concrete control or row — never the
/// navigation bar title.
enum KCConfirmation {
    /// Regular horizontal size class (iPad) needs an explicit popover source.
    static func needsPopoverAnchor(for host: UIViewController) -> Bool {
        host.traitCollection.horizontalSizeClass == .regular
    }

    /// Configures iPad popover anchoring only. Returns whether a popover was configured.
    @discardableResult
    static func configurePopoverIfNeeded(
        for presented: UIViewController,
        host: UIViewController,
        sourceView: UIView? = nil,
        sourceRect: CGRect? = nil,
        barButtonItem: UIBarButtonItem? = nil
    ) -> Bool {
        guard needsPopoverAnchor(for: host),
              let pop = presented.popoverPresentationController
        else {
            return false
        }

        if let barButtonItem {
            pop.barButtonItem = barButtonItem
        } else if let sourceView {
            pop.sourceView = sourceView
            pop.sourceRect = sourceRect ?? sourceView.bounds
            pop.permittedArrowDirections = [.up, .down]
        } else {
            // Centered, no arrow — never the nav title / large-title label.
            let bounds = host.view.bounds
            pop.sourceView = host.view
            pop.sourceRect = CGRect(x: bounds.midX - 1, y: bounds.midY - 1, width: 2, height: 2)
            pop.permittedArrowDirections = []
        }
        return true
    }

    /// Presents a `.actionSheet` as a bottom confirmation on iPhone; popover on iPad.
    static func presentActionSheet(
        _ alert: UIAlertController,
        from host: UIViewController,
        sourceView: UIView? = nil,
        sourceRect: CGRect? = nil,
        barButtonItem: UIBarButtonItem? = nil
    ) {
        precondition(
            alert.preferredStyle == .actionSheet,
            "KCConfirmation.presentActionSheet requires preferredStyle == .actionSheet"
        )
        _ = configurePopoverIfNeeded(
            for: alert,
            host: host,
            sourceView: sourceView,
            sourceRect: sourceRect,
            barButtonItem: barButtonItem
        )
        host.present(alert, animated: true)
    }

    /// Share sheet with the same iPhone/iPad anchoring rules.
    static func presentActivity(
        _ activity: UIActivityViewController,
        from host: UIViewController,
        sourceView: UIView? = nil,
        sourceRect: CGRect? = nil,
        barButtonItem: UIBarButtonItem? = nil
    ) {
        _ = configurePopoverIfNeeded(
            for: activity,
            host: host,
            sourceView: sourceView,
            sourceRect: sourceRect,
            barButtonItem: barButtonItem
        )
        host.present(activity, animated: true)
    }
}
