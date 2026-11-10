import Foundation
import UIKit
import UserNotifications

/// Pure-native APNs (no Capacitor PushNotifications plugin).
/// Registers the device token with `/api/native/v1/devices/apns` using the Keychain bearer.
/// Device token itself is stored in the Keychain (not UserDefaults).
@MainActor
final class NativePushService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NativePushService()

    private static let legacyTokenKey = "katecheo.apns-token.v1"
    private static let enabledKey = "katecheo.apns-enabled.v1"

    private(set) var lastTokenHex: String? {
        didSet {
            _ = KeychainStore.setApnsToken(lastTokenHex)
            // Clear any leftover plaintext token from older builds.
            UserDefaults.standard.removeObject(forKey: Self.legacyTokenKey)
        }
    }

    private override init() {
        super.init()
        if let keyed = KeychainStore.apnsToken(), !keyed.isEmpty {
            lastTokenHex = keyed
        } else if let legacy = UserDefaults.standard.string(forKey: Self.legacyTokenKey), !legacy.isEmpty {
            // One-time migrate UserDefaults → Keychain.
            _ = KeychainStore.setApnsToken(legacy)
            UserDefaults.standard.removeObject(forKey: Self.legacyTokenKey)
            lastTokenHex = legacy
        }
    }

    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
    }

    /// Request permission + register with APNs. Call after sign-in or from Avisos.
    @discardableResult
    func enable() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else { return false }
            UIApplication.shared.registerForRemoteNotifications()
            UserDefaults.standard.set(true, forKey: Self.enabledKey)
            return true
        } catch {
            return false
        }
    }

    /// Re-register if the user previously enabled push (cold start).
    func resumeIfNeeded() {
        guard UserDefaults.standard.bool(forKey: Self.enabledKey) else { return }
        guard NativeAPIClient.hasBearer else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    func handleDeviceToken(_ deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        lastTokenHex = hex
        Task { await uploadToken(hex) }
    }

    func handleRegistrationError(_ error: Error) {
        #if DEBUG
        print("[NativePush] registration failed: \(error.localizedDescription)")
        #endif
    }

    func disable() async {
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        let token = lastTokenHex ?? KeychainStore.apnsToken() ?? ""
        UIApplication.shared.unregisterForRemoteNotifications()
        if !token.isEmpty, NativeAPIClient.hasBearer {
            try? await NativeAPIClient.dropApnsDevice(token: token)
        }
        UserDefaults.standard.removeObject(forKey: Self.legacyTokenKey)
        _ = KeychainStore.deleteApnsToken()
        lastTokenHex = nil
    }

    private func uploadToken(_ token: String) async {
        guard NativeAPIClient.hasBearer else { return }
        do {
            try await NativeAPIClient.saveApnsDevice(token: token, sandbox: Self.apnsSandbox)
            #if DEBUG
            print("[NativePush] token saved sandbox=\(Self.apnsSandbox)")
            #endif
        } catch {
            #if DEBUG
            print("[NativePush] save failed: \(error.localizedDescription)")
            #endif
        }
    }

    private static var apnsSandbox: Bool {
        let raw = Bundle.main.object(forInfoDictionaryKey: "KatecheoApnsSandbox")
        if let value = raw as? Bool { return value }
        if let value = raw as? String {
            return value == "YES" || value == "true" || value == "1"
        }
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        let type = (userInfo["type"] as? String)
            ?? ((userInfo["data"] as? [String: Any])?["type"] as? String)
        if type == "themes_updated" || type == "reading_updated" {
            DispatchQueue.main.async {
                NativeCatalogSync.handleSilentPush(type: type)
            }
            // Catalog hints are silent — never surface a banner.
            completionHandler([])
            return
        }
        let title = notification.request.content.title
        DispatchQueue.main.async {
            Self.ingestActivity(from: userInfo, title: title)
        }
        completionHandler([.banner, .sound, .badge])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let href = (userInfo["href"] as? String)
            ?? ((userInfo["data"] as? [String: Any])?["href"] as? String)
        let title = response.notification.request.content.title
        DispatchQueue.main.async {
            Self.ingestActivity(from: userInfo, title: title)
            if let href, !href.isEmpty {
                NativeDeepLinkRouter.open(href: href)
            }
        }
        completionHandler()
    }

    @MainActor
    private static func ingestActivity(from userInfo: [AnyHashable: Any], title: String) {
        let href = (userInfo["href"] as? String)
            ?? ((userInfo["data"] as? [String: Any])?["href"] as? String)
        // Do not light dots from the payload alone — confirm via server state for this account.
        Task { @MainActor in
            await KCActivitySync.handlePushHint(
                href: href,
                title: title.isEmpty ? nil : title
            )
        }
    }
}
