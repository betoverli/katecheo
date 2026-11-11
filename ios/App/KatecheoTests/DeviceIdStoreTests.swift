import XCTest
@testable import Katecheo

final class DeviceIdStoreTests: XCTestCase {
    override func tearDown() {
        _ = KeychainStore.deleteDeviceId()
        super.tearDown()
    }

    func testDeviceId_usesVendorAndPersistsAcrossCalls() {
        _ = KeychainStore.deleteDeviceId()
        let vendor = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        let first = DeviceIdStore.deviceId(vendorId: vendor)
        XCTAssertEqual(first, vendor)

        // A different vendor id must not replace the Keychain value.
        let second = DeviceIdStore.deviceId(vendorId: "FFFF-1111-2222-3333-444444444444")
        XCTAssertEqual(second, vendor)
        XCTAssertEqual(KeychainStore.deviceId(), vendor)
    }

    func testDeviceId_fallsBackToUUIDWhenVendorMissing() {
        _ = KeychainStore.deleteDeviceId()
        let id = DeviceIdStore.deviceId(vendorId: nil)
        XCTAssertGreaterThanOrEqual(id.count, 8)
        XCTAssertEqual(DeviceIdStore.deviceId(vendorId: "IGNORED-AFTER-PERSIST"), id)
    }
}
