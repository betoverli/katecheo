import Foundation
import Security

/// Small Keychain helper for the Better Auth bearer, APNs device token, and stable device id.
enum KeychainStore {
    static let bearerService = "katecheo.auth"
    static let bearerAccount = "bearer-token"
    static let apnsService = "katecheo.apns"
    static let apnsAccount = "device-token"
    static let deviceIdService = "katecheo.device"
    static let deviceIdAccount = "stable-device-id"

    @discardableResult
    static func setBearerToken(_ token: String?) -> Bool {
        deleteBearerToken()
        guard let token, !token.isEmpty, let data = token.data(using: .utf8) else {
            return token == nil || token?.isEmpty == true
        }
        return add(service: bearerService, account: bearerAccount, data: data)
    }

    static func bearerToken() -> String? {
        readString(service: bearerService, account: bearerAccount)
    }

    @discardableResult
    static func deleteBearerToken() -> Bool {
        delete(service: bearerService, account: bearerAccount)
    }

    // MARK: - APNs device token

    @discardableResult
    static func setApnsToken(_ token: String?) -> Bool {
        deleteApnsToken()
        guard let token, !token.isEmpty, let data = token.data(using: .utf8) else {
            return token == nil || token?.isEmpty == true
        }
        return add(service: apnsService, account: apnsAccount, data: data)
    }

    static func apnsToken() -> String? {
        readString(service: apnsService, account: apnsAccount)
    }

    @discardableResult
    static func deleteApnsToken() -> Bool {
        delete(service: apnsService, account: apnsAccount)
    }

    // MARK: - Stable device id (survives reinstall when Keychain retains the item)

    @discardableResult
    static func setDeviceId(_ deviceId: String?) -> Bool {
        deleteDeviceId()
        guard let deviceId, !deviceId.isEmpty, let data = deviceId.data(using: .utf8) else {
            return deviceId == nil || deviceId?.isEmpty == true
        }
        return add(service: deviceIdService, account: deviceIdAccount, data: data)
    }

    static func deviceId() -> String? {
        readString(service: deviceIdService, account: deviceIdAccount)
    }

    @discardableResult
    static func deleteDeviceId() -> Bool {
        delete(service: deviceIdService, account: deviceIdAccount)
    }

    // MARK: - Internals

    private static func add(service: String, account: String, data: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    private static func readString(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func delete(service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
