import XCTest
@testable import Zap

/// Tests persistence and accessors for the per-display scope modes.
final class ScreenScopePreferencesTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "com.zapapp.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsToOffForUnknownDisplay() {
        let prefs = Preferences(defaults: defaults)
        XCTAssertTrue(prefs.screenScopeModes.isEmpty)
        XCTAssertEqual(prefs.screenScopeMode(forID: "display-X"), .off)
        XCTAssertFalse(prefs.hasAnyScreenScoped)
    }

    func testSetModeRoundTrips() {
        let prefs = Preferences(defaults: defaults)
        prefs.setScreenScopeMode(.scopedIgnoringExclusions, forID: "display-A")
        XCTAssertTrue(prefs.hasAnyScreenScoped)

        let reloaded = Preferences(defaults: defaults)
        XCTAssertEqual(reloaded.screenScopeMode(forID: "display-A"), .scopedIgnoringExclusions)
    }

    func testSettingOffRemovesTheEntry() {
        let prefs = Preferences(defaults: defaults)
        prefs.setScreenScopeMode(.scopedRespectingExclusions, forID: "display-A")
        prefs.setScreenScopeMode(.off, forID: "display-A")

        XCTAssertTrue(prefs.screenScopeModes.isEmpty)
        XCTAssertFalse(prefs.hasAnyScreenScoped)

        // And the absence persists rather than storing "off".
        let reloaded = Preferences(defaults: defaults)
        XCTAssertTrue(reloaded.screenScopeModes.isEmpty)
    }

    func testCorruptStoredValuesAreDropped() {
        defaults.set(["display-A": "scopedRespectingExclusions",
                      "display-B": "nonsense",
                      "display-C": "off"],          // off should never round-trip as an entry
                     forKey: "screenScopeModes")
        let prefs = Preferences(defaults: defaults)
        XCTAssertEqual(prefs.screenScopeMode(forID: "display-A"), .scopedRespectingExclusions)
        XCTAssertEqual(prefs.screenScopeMode(forID: "display-B"), .off)
        XCTAssertEqual(prefs.screenScopeMode(forID: "display-C"), .off)
        XCTAssertEqual(prefs.screenScopeModes.count, 1)
    }
}
