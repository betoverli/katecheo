import UIKit
import WebKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        window = UIWindow(windowScene: windowScene)
        window?.tintColor = V2NDesign.accent
        // Apply saved Appearance BEFORE the first frame (TF219) — never force system.
        AppAppearance.syncFromCacheAndApply()
        AppAppearance.apply(to: window)
        window?.rootViewController = AppRoot.makeRootViewController()
        window?.makeKeyAndVisible()
        // Re-assert after the window is key (covers late scene attachment).
        AppAppearance.apply(to: window)

        // Existing Cap users: cookie → Keychain, then one-time localStorage import.
        // Must stay on main — WebKit data-store / importer init off-main crashes.
        Task { @MainActor in
            let migrated = await NativeSessionBootstrap.migrateCookieToKeychainIfNeeded()
            if migrated {
                NotificationCenter.default.post(name: .nativeSessionDidChange, object: nil)
            }
            await LegacyWebStorageImporter.runIfNeeded()
            await NativeOutbox.flushIfPossible()
            NativePushService.shared.resumeIfNeeded()
        }

        NotificationCenter.default.addObserver(
            forName: .nativeSessionDidExpire,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.presentReLoginIfNeeded()
        }

        NotificationCenter.default.addObserver(
            forName: .nativeSessionDidChange,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                await NativeOutbox.flushIfPossible()
                // Account switch / login — always reconcile.
                await V2NActivitySync.refreshFromServer(force: true)
            }
        }

        // Cold-start deep links / universal links / push taps.
        if let url = connectionOptions.urlContexts.first?.url {
            DispatchQueue.main.async {
                NativeDeepLinkRouter.open(url: url)
            }
        }
        if let activity = connectionOptions.userActivities.first(where: { $0.activityType == NSUserActivityTypeBrowsingWeb }),
           let url = activity.webpageURL
        {
            DispatchQueue.main.async {
                NativeDeepLinkRouter.open(url: url)
            }
        }
        if let response = connectionOptions.notificationResponse {
            let userInfo = response.notification.request.content.userInfo
            let href = (userInfo["href"] as? String)
                ?? ((userInfo["data"] as? [String: Any])?["href"] as? String)
            if let href {
                DispatchQueue.main.async {
                    NativeDeepLinkRouter.open(href: href)
                }
            }
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        NativeDeepLinkRouter.open(url: url)
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL
        else { return }
        NativeDeepLinkRouter.open(url: url)
    }

    func sceneWillResignActive(_ scene: UIScene) {
        flushWebViewCookies()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        flushWebViewCookies()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Keep Appearance on every window (sheets / late scene windows) — TF219.
        AppAppearance.apply(to: window)
        Task { @MainActor in
            await NativeOutbox.flushIfPossible()
            // Debounced unless TTL elapsed (push path forces separately).
            await V2NActivitySync.refreshFromServer(force: false)
            // Cheap Themes/Reading etag — fallback when a silent push was missed.
            await NativeCatalogSync.checkVersionsOnForeground()
        }
    }

    private func presentReLoginIfNeeded() {
        guard let root = window?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        if top is NativeSignInViewController { return }
        if let nav = top as? UINavigationController,
           nav.viewControllers.first is NativeSignInViewController
        {
            return
        }
        let signIn = NativeSignInViewController()
        signIn.onSignedIn = {
            NotificationCenter.default.post(name: .nativeSessionDidChange, object: nil)
            Task { @MainActor in
                await LegacyWebStorageImporter.runIfNeeded()
                await NativeOutbox.flushIfPossible()
            }
        }
        let nav = UINavigationController(rootViewController: signIn)
        nav.modalPresentationStyle = .fullScreen
        top.present(nav, animated: true)
    }
}

extension Notification.Name {
    static let nativeSessionDidChange = Notification.Name("verse2note.nativeSessionDidChange")
    static let nativeNoteDidChange = Notification.Name("verse2note.nativeNoteDidChange")
}

/// Cookie jar flush for legacy Cap → Keychain migration. Safe no-op when empty.
private func flushWebViewCookies() {
    WKWebsiteDataStore.default().httpCookieStore.getAllCookies { _ in }
}
