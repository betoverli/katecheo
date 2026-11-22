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
        nav.isModalInPresentation = false
        // Inherit host Light override so editor sheets match canvas when
        // "Editor sempre claro" is on (build-238).
        if host.overrideUserInterfaceStyle != .unspecified {
            nav.overrideUserInterfaceStyle = host.overrideUserInterfaceStyle
            viewController.overrideUserInterfaceStyle = host.overrideUserInterfaceStyle
        }

        let regular = host.traitCollection.horizontalSizeClass == .regular
        if regular {
            // iPad: formSheet-like size — medium page-sheet detent looks tiny in a wide window.
            nav.modalPresentationStyle = .formSheet
            nav.preferredContentSize = CGSize(width: 540, height: 640)
            if let sheet = nav.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.selectedDetentIdentifier = .large
                sheet.prefersGrabberVisible = true
                sheet.prefersScrollingExpandsWhenScrolledToEdge = true
            }
        } else {
            nav.modalPresentationStyle = .pageSheet
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
        }
        host.present(nav, animated: true)
    }
}
