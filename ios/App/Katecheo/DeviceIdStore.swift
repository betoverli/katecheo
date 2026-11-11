import Foundation
import UIKit

/// Stable installation/device id for APNs registration.
///
/// Resolution order:
/// 1. Process memory (same launch)
/// 2. Keychain (survives many reinstalls / TestFlight updates)
/// 3. UserDefaults (same install when Keychain is unavailable, e.g. unsigned CI)
/// 4. `identifierForVendor` (stable across reinstalls while another app from the vendor remains)
/// 5. Fresh UUID, then persisted
enum DeviceIdStore {
    /// Shared with unit tests that simulate a relaunch via UserDefaults only.
    static let defaultsKey = "katecheo.stable-device-id.v1"
    private static var memory: String?

    /// Clears in-memory + UserDefaults + Keychain (unit tests only).
    static func resetForTests() {
        memory = nil
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        _ = KeychainStore.deleteDeviceId()
    }

    /// Resolve (and persist) the stable device id.
    /// - Parameter vendorId: injectable for unit tests; defaults to `identifierForVendor`.
    static func deviceId(vendorId: String? = UIDevice.current.identifierForVendor?.uuidString) -> String {
        if let memory, memory.count >= 8 {
            return memory
        }

        if let keyed = KeychainStore.deviceId()?.trimmingCharacters(in: .whitespacesAndNewlines),
           keyed.count >= 8 {
            return adopt(keyed)
        }

        if let stored = UserDefaults.standard.string(forKey: defaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           stored.count >= 8 {
            // Keychain may have been unavailable earlier — retry write-through.
            _ = KeychainStore.setDeviceId(stored)
            return adopt(stored, writeKeychain: false)
        }

        let trimmedVendor = vendorId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolved = trimmedVendor.count >= 8 ? trimmedVendor : UUID().uuidString
        return adopt(resolved)
    }

    @discardableResult
    private static func adopt(_ value: String, writeKeychain: Bool = true) -> String {
        memory = value
        UserDefaults.standard.set(value, forKey: defaultsKey)
        if writeKeychain {
            _ = KeychainStore.setDeviceId(value)
        }
        return value
    }
}
