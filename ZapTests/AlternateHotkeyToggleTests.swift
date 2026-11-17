import CoreGraphics
import XCTest
@testable import Zap

/// Flipping "Use ⌥-Tab instead of ⌘-Tab" in Settings must reconfigure the
/// trigger to the new value right away. `@Published` emits before it stores,
/// so a subscriber that reads the preference back sees the old value and
/// reapplies the trigger the user just switched away from.
final class AlternateHotkeyToggleTests: XCTestCase {
    private final class Connection: EventTapConnection {
        var isValid = true
        var isEnabled = false
        let registeredEvents: CGEventMask? = EventTapMonitor.requiredEvents

        func setEnabled(_ enabled: Bool) { isEnabled = enabled }
        func invalidate() {
            isValid = false
            isEnabled = false
        }
    }

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var preferences: Preferences!
    private var connection: Connection!
    private var switcher: SwitcherController!

    override func setUp() {
        super.setUp()
        suiteName = "ch.lkmc.Zap.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        preferences = Preferences(defaults: defaults)
        let connection = Connection()
        self.connection = connection
        // Trusted, with a tap that always installs, so ⌘-Tab is available and
        // only the preference decides between it and ⌥-Tab.
        switcher = SwitcherController(
            preferences: preferences,
            eventTap: EventTapMonitor(makeConnection: { _, _, _ in connection }),
            isAccessibilityTrusted: { true }
        )
    }

    override func tearDown() {
        switcher.pause()   // releases the ⌥-Tab hotkey if one was registered
        switcher = nil
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testTurningTheAlternateHotkeyOnReleasesCommandTab() {
        switcher.start()
        XCTAssertTrue(switcher.isUsingEventTap)

        preferences.useAlternateHotkey = true

        XCTAssertTrue(waitUntil { !self.switcher.isUsingEventTap },
                      "⌘-Tab is still intercepted after choosing ⌥-Tab")
        XCTAssertFalse(connection.isEnabled)
        XCTAssertFalse(connection.isValid, "the tap should be torn down, not just disabled")
    }

    func testTurningTheAlternateHotkeyOffTakesCommandTabBack() {
        preferences.useAlternateHotkey = true
        switcher.start()
        XCTAssertFalse(switcher.isUsingEventTap)

        preferences.useAlternateHotkey = false

        // Well under the 2 s input-health poll, which would otherwise repair
        // the mode later and hide the bug.
        XCTAssertTrue(waitUntil { self.switcher.isUsingEventTap },
                      "⌘-Tab isn't intercepted after turning ⌥-Tab off")
        XCTAssertTrue(connection.isEnabled)
    }

    // MARK: Helpers

    /// Runs the main run loop until `condition` holds or `timeout` passes.
    private func waitUntil(timeout: TimeInterval = 0.5, _ condition: () -> Bool) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while !condition() && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        return condition()
    }
}
