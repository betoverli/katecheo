import UIKit

/// Shared presentation for editor modals (speaker picker, bible ref, note settings).
/// Web `ViewportSheet` dismisses on backdrop tap — configure page sheets the same way.
enum KCSheetPresenter {
    static func present(_ viewController: UIViewController, from host: UIViewController) {
        let nav: UINavigationController
        if let existing = viewController as? UINavigationController {
            nav = existing
        } else {
            nav = UINavigationController(rootViewController: viewController)
        }
        nav.modalPresentationStyle = .pageSheet
        nav.isModalInPresentation = false
        if let sheet = nav.sheetPresentationController {
            // Medium detent leaves a dimmed region above the sheet so outside taps dismiss
            // (large-only sheets cover the phone and have no backdrop target).
            sheet.detents = [.medium(), .large()]
            sheet.selectedDetentIdentifier = .medium
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
            sheet.largestUndimmedDetentIdentifier = nil
            sheet.prefersEdgeAttachedInCompactHeight = true
        }
        // Inherit host Light override so editor sheets match canvas when
        // "Editor sempre claro" is on (build-238).
        if host.overrideUserInterfaceStyle != .unspecified {
            nav.overrideUserInterfaceStyle = host.overrideUserInterfaceStyle
            viewController.overrideUserInterfaceStyle = host.overrideUserInterfaceStyle
        }
        host.present(nav, animated: true)
    }
}
