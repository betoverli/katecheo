import XCTest
@testable import Katecheo

/// Caderno / Grupos rows must use warm accentSoft selection — never system blue-gray.
@MainActor
final class WarmSelectionTests: XCTestCase {
    func testNoteRow_highlightedUsesAccentSoft() {
        let cell = KCNoteRowCell(style: .default, reuseIdentifier: KCNoteRowCell.reuseId)
        cell.applySidebarStyle(isPadSidebar: false)
        cell.setHighlighted(true, animated: false)
        cell.setNeedsUpdateConfiguration()
        cell.updateConfiguration(using: cell.configurationState)

        let fill = cell.testing_backgroundConfigurationColor?
            .resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let expected = KCDesign.accentSoft.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        XCTAssertEqual(fill, expected)
    }

    func testNoteRow_selectedPadSidebarUsesAccentSoft() {
        let cell = KCNoteRowCell(style: .default, reuseIdentifier: KCNoteRowCell.reuseId)
        cell.applySidebarStyle(isPadSidebar: true)
        cell.setSelected(true, animated: false)
        cell.setNeedsUpdateConfiguration()
        cell.updateConfiguration(using: cell.configurationState)

        let fill = cell.testing_backgroundConfigurationColor?
            .resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        let expected = KCDesign.accentSoft.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        XCTAssertEqual(fill, expected)
        XCTAssertTrue(cell.testing_usesPadSidebarStyle)
    }

    func testGroupRow_idleGroupedUsesSurface() {
        let cell = KCGroupRowCell(style: .default, reuseIdentifier: KCGroupRowCell.reuseId)
        cell.applySidebarStyle(isPadSidebar: false)
        cell.setSelected(false, animated: false)
        cell.setHighlighted(false, animated: false)
        cell.setNeedsUpdateConfiguration()
        cell.updateConfiguration(using: cell.configurationState)

        let fill = cell.testing_backgroundConfigurationColor?
            .resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let expected = KCDesign.surface.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        XCTAssertEqual(fill, expected)
    }

    func testGroupRow_highlightedUsesAccentSoft() {
        let cell = KCGroupRowCell(style: .default, reuseIdentifier: KCGroupRowCell.reuseId)
        cell.applySidebarStyle(isPadSidebar: false)
        cell.setHighlighted(true, animated: false)
        cell.setNeedsUpdateConfiguration()
        cell.updateConfiguration(using: cell.configurationState)

        let fill = cell.testing_backgroundConfigurationColor?
            .resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let expected = KCDesign.accentSoft.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        XCTAssertEqual(fill, expected)
    }
}
