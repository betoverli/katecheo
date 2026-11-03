import Foundation
import UIKit
import UserNotifications

/// Pure-native APNs (no Capacitor PushNotifications plugin).
/// Registers the device token with `/api/native/v1/devices/apns` using the Keychain bearer.
@MainActor
final class NativePushService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NativePushService()

    private static let tokenKey = "verse2note.apns-token.v1"
    private static let enabledKey = "verse2note.apns-enabled.v1"

    private(set) var lastTokenHex: String? {
        didSet {
            if let lastTokenHex {
                UserDefaults.standard.set(lastTokenHex, forKey: Self.tokenKey)
            }
        }
    }

    private override init() {
        super.init()
        lastTokenHex = UserDefaults.standard.string(forKey: Self.tokenKey)
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
        print("[NativePush] registration failed: \(error.localizedDescription)")
    }

    func disable() async {
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        let token = lastTokenHex ?? UserDefaults.standard.string(forKey: Self.tokenKey) ?? ""
        UIApplication.shared.unregisterForRemoteNotifications()
        if !token.isEmpty, NativeAPIClient.hasBearer {
            try? await NativeAPIClient.dropApnsDevice(token: token)
        }
        UserDefaults.standard.removeObject(forKey: Self.tokenKey)
        lastTokenHex = nil
    }

    private func uploadToken(_ token: String) async {
        guard NativeAPIClient.hasBearer else { return }
        do {
            try await NativeAPIClient.saveApnsDevice(token: token, sandbox: Self.apnsSandbox)
            print("[NativePush] token saved sandbox=\(Self.apnsSandbox)")
        } catch {
            print("[NativePush] save failed: \(error.localizedDescription)")
        }
    }

    private static var apnsSandbox: Bool {
        let raw = Bundle.main.object(forInfoDictionaryKey: "Verse2NoteApnsSandbox")
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
        if let href, !href.isEmpty {
            DispatchQueue.main.async {
                NativeDeepLinkRouter.open(href: href)
            }
        }
        completionHandler()
    }
}
