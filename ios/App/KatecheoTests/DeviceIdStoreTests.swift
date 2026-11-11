import XCTest
@testable import Katecheo

final class DeviceIdStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        DeviceIdStore.resetForTests()
    }

    override func tearDown() {
        DeviceIdStore.resetForTests()
        super.tearDown()
    }

    func testDeviceId_usesVendorAndPersistsAcrossCalls() {
        let vendor = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        let first = DeviceIdStore.deviceId(vendorId: vendor)
        XCTAssertEqual(first, vendor)

        // A different vendor id must not replace the already-adopted stable id.
        let second = DeviceIdStore.deviceId(vendorId: "FFFF-1111-2222-3333-444444444444")
        XCTAssertEqual(second, vendor)
    }

    func testDeviceId_fallsBackToUUIDWhenVendorMissing() {
        let id = DeviceIdStore.deviceId(vendorId: nil)
        XCTAssertGreaterThanOrEqual(id.count, 8)
        XCTAssertEqual(DeviceIdStore.deviceId(vendorId: "IGNORED-AFTER-PERSIST"), id)
    }

    func testDeviceId_survivesMemoryClearViaUserDefaults() {
        let vendor = "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF"
        let first = DeviceIdStore.deviceId(vendorId: vendor)
        // Simulate a new process: clear memory only, keep UserDefaults/Keychain.
        DeviceIdStore.resetForTests()
        // Put the value back only in UserDefaults (Keychain may be unavailable in unsigned CI).
        UserDefaults.standard.set(first, forKey: DeviceIdStore.defaultsKey)
        let second = DeviceIdStore.deviceId(vendorId: "DIFFERENT-VENDOR-AFTER-RELAUNCH")
        XCTAssertEqual(second, first)
    }
}
