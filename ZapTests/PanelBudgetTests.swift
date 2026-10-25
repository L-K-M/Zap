import XCTest
@testable import Zap

/// The analytic height budget for the panel's window section (see
/// `PanelBudget`), shared by `OverlayView` (which clips/scrolls the section) and
/// `OverlayWindowController` (which must know whether a vertical scroll gesture
/// belongs to the section or to the icon row).
///
/// Every element below the header grows the panel *downward* from its fixed top
/// edge, so anything that can appear (search badge, help footer) must be
/// reserved; under-reserving makes the frame clamp shift the panel up, moving
/// the icon row (mimo.md §1 / ANALYSIS.md B7).
final class PanelBudgetTests: XCTestCase {

    private let header: CGFloat = 140
    private let divider: CGFloat = 30
    private let badge: CGFloat = 33
    private let help: CGFloat = 60
    private let minimum: CGFloat = 30

    private func budget(searchBadge: Bool, showsHelp: Bool, maxPanelHeight: CGFloat = 600) -> CGFloat {
        PanelBudget.windowSectionBudget(maxPanelHeight: maxPanelHeight,
                                        headerHeight: header,
                                        dividerReserve: divider,
                                        searchBadgeReserve: badge,
                                        showsSearchBadge: searchBadge,
                                        helpFooterReserve: help,
                                        showsHelp: showsHelp,
                                        minimum: minimum)
    }

    func testBudgetReservesHeaderAndDivider() {
        XCTAssertEqual(budget(searchBadge: false, showsHelp: false), 600 - 140 - 30)
    }

    func testSearchBadgeIsReservedWhileAQueryIsTyped() {
        XCTAssertEqual(budget(searchBadge: true, showsHelp: false), 600 - 140 - 30 - 33)
    }

    func testHelpFooterIsReservedWhileHintsShow() {
        XCTAssertEqual(budget(searchBadge: false, showsHelp: true), 600 - 140 - 30 - 60)
    }

    func testEveryReserveAppliesTogether() {
        XCTAssertEqual(budget(searchBadge: true, showsHelp: true), 600 - 140 - 30 - 33 - 60)
    }

    func testBudgetNeverDropsBelowOneCell() {
        XCTAssertEqual(budget(searchBadge: true, showsHelp: true, maxPanelHeight: 100), minimum)
    }

    // MARK: Header

    func testHeaderHeightWithoutNameLine() {
        XCTAssertEqual(PanelBudget.headerHeight(contentPadding: 20, cellWidth: 96,
                                                showsAppName: false), 20 * 2 + 96)
    }

    func testHeaderHeightWithNameLine() {
        XCTAssertEqual(PanelBudget.headerHeight(contentPadding: 20, cellWidth: 96,
                                                showsAppName: true),
                       20 * 2 + 96 + PanelBudget.nameLineHeight + PanelBudget.sectionSpacing)
    }

    // MARK: Scroll gate

    func testSectionScrollsOnlyWhenItOutgrowsTheBudget() {
        XCTAssertTrue(PanelBudget.scrolls(naturalHeight: 301, budget: 300))
        XCTAssertFalse(PanelBudget.scrolls(naturalHeight: 300, budget: 300))
        XCTAssertFalse(PanelBudget.scrolls(naturalHeight: 100, budget: 300))
    }
}
