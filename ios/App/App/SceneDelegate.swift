import UIKit
import Capacitor
import WebKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var modeObserver: NSObjectProtocol?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        window = UIWindow(windowScene: windowScene)
        window?.rootViewController = AppRoot.makeRootViewController()
        window?.makeKeyAndVisible()

        modeObserver = NotificationCenter.default.addObserver(
            forName: NativeShellMode.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let window = self?.window else { return }
            let next = AppRoot.makeRootViewController()
            UIView.transition(with: window, duration: 0.28, options: .transitionCrossDissolve, animations: {
                window.rootViewController = next
            })
        }

        // Existing Cap users: copy web session cookie into Keychain before notes load.
        Task { @MainActor in
            let migrated = await NativeSessionBootstrap.migrateCookieToKeychainIfNeeded()
            if migrated {
                NotificationCenter.default.post(name: .nativeSessionDidChange, object: nil)
            }
        }

        SceneDelegateProxy.shared.scene(scene, willConnectTo: session, options: connectionOptions)
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        SceneDelegateProxy.shared.scene(scene, openURLContexts: URLContexts)
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        SceneDelegateProxy.shared.scene(scene, continue: userActivity)
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

/// WKWebView writes cookies asynchronously. Reading the store is what pushes
/// that write to disk, so an HttpOnly session cookie is still there after the
/// process is killed. `__Host-` cookies cannot be recreated from JavaScript.
private func flushWebViewCookies() {
    WKWebsiteDataStore.default().httpCookieStore.getAllCookies { _ in }
}
