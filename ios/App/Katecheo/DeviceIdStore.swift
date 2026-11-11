import Foundation
import UIKit

/// Stable installation/device id for APNs registration.
/// Prefers a Keychain value (survives TestFlight updates / many reinstalls),
/// then `identifierForVendor`, then a fresh UUID persisted in Keychain.
enum DeviceIdStore {
    /// Resolve (and persist) the stable device id.
    /// - Parameter vendorId: injectable for unit tests; defaults to `identifierForVendor`.
    static func deviceId(vendorId: String? = UIDevice.current.identifierForVendor?.uuidString) -> String {
        if let existing = KeychainStore.deviceId()?.trimmingCharacters(in: .whitespacesAndNewlines),
           existing.count >= 8 {
            return existing
        }
        let trimmedVendor = vendorId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolved = trimmedVendor.count >= 8 ? trimmedVendor : UUID().uuidString
        _ = KeychainStore.setDeviceId(resolved)
        return resolved
    }
}
