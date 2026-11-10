import XCTest
@testable import Katecheo

final class KCScrollChromeTests: XCTestCase {
    func testTabBarClearance_whenFloatingBarTallerThanSafeArea() {
        // Liquid Glass floating tab ~83pt over home-indicator safe area ~34pt.
        let clearance = KCScrollChrome.tabBarClearance(
            tabBarHeight: 83,
            safeAreaBottom: 34,
            tabBarMinYInView: 800,
            viewHeight: 844
        )
        // height-safeArea = 49; overlap = 844-800-34 = 10 → max is 49 + md.
        XCTAssertEqual(clearance, 49 + KCDesign.Space.md, accuracy: 0.5)
    }

    func testTabBarClearance_usesOverlapWhenLarger() {
        let clearance = KCScrollChrome.tabBarClearance(
            tabBarHeight: 49,
            safeAreaBottom: 34,
            tabBarMinYInView: 700,
            viewHeight: 844
        )
        // overlap = 844 - 700 - 34 = 110
        XCTAssertEqual(clearance, 110 + KCDesign.Space.md, accuracy: 0.5)
    }

    func testTabBarClearance_zeroWhenNoTabBar() {
        let clearance = KCScrollChrome.tabBarClearance(
            tabBarHeight: 0,
            safeAreaBottom: 34,
            tabBarMinYInView: nil,
            viewHeight: 844
        )
        XCTAssertEqual(clearance, 0, accuracy: 0.1)
    }
}
