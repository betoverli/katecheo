import UIKit
import WebKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        window = UIWindow(windowScene: windowScene)
        window?.rootViewController = AppRoot.makeRootViewController()
        window?.makeKeyAndVisible()

        // Existing Cap users: copy web session cookie into Keychain before notes load.
        // Must stay on main — WKWebsiteDataStore init off-main crashes WebKit.
        Task { @MainActor in
            let migrated = await NativeSessionBootstrap.migrateCookieToKeychainIfNeeded()
            if migrated {
                NotificationCenter.default.post(name: .nativeSessionDidChange, object: nil)
            }
            NativePushService.shared.resumeIfNeeded()
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
}

extension Notification.Name {
    static let nativeSessionDidChange = Notification.Name("verse2note.nativeSessionDidChange")
    static let nativeNoteDidChange = Notification.Name("verse2note.nativeNoteDidChange")
}

/// Cookie jar flush for legacy Cap → Keychain migration. Safe no-op when empty.
private func flushWebViewCookies() {
    WKWebsiteDataStore.default().httpCookieStore.getAllCookies { _ in }
}
