import UIKit
import UserNotifications

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        V2NChrome.applyAppWide()
        // Seed Appearance from cache early so SceneDelegate windows inherit the right style.
        AppAppearance.syncFromCacheAndApply()
        NativePushService.shared.configure()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in
            NativePushService.shared.handleDeviceToken(deviceToken)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in
            NativePushService.shared.handleRegistrationError(error)
        }
    }

    /// Silent / background catalog hints (`content-available: 1`, type themes_updated | reading_updated).
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        let type = (userInfo["type"] as? String)
            ?? ((userInfo["data"] as? [String: Any])?["type"] as? String)
        Task { @MainActor in
            if let type, type == "themes_updated" || type == "reading_updated" {
                NativeCatalogSync.handleSilentPush(type: type)
                completionHandler(.newData)
                return
            }
            // Existing activity reconcile path (alert pushes also land here when content-available).
            let href = (userInfo["href"] as? String)
                ?? ((userInfo["data"] as? [String: Any])?["href"] as? String)
            let title = (userInfo["aps"] as? [String: Any]).flatMap { aps in
                (aps["alert"] as? [String: Any])?["title"] as? String
                    ?? aps["alert"] as? String
            }
            await V2NActivitySync.handlePushHint(href: href, title: title)
            completionHandler(.newData)
        }
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default Configuration",
                                          sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}
