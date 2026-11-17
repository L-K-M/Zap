import CoreGraphics
import XCTest
@testable import Zap

/// Key-state bookkeeping and re-enable rules in `EventTapMonitor`, driven
/// through the tap callback with synthesized events. A wrong answer here
/// leaks into every app on the Mac: a swallowed key-up leaves a key "stuck"
/// down, and a tap that switches itself back on swallows ⌘-Tab while paused.
final class EventTapKeyStateTests: XCTestCase {
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

    private static let qKeyCode: CGKeyCode = 12   // types "q" on US, matched by character anyway

    private var connection: Connection!
    private var monitor: EventTapMonitor!
    private var callback: CGEventTapCallBack!
    private var refcon: UnsafeMutableRawPointer!
    private var switching = false

    override func setUp() {
        super.setUp()
        let connection = Connection()
        self.connection = connection
        monitor = EventTapMonitor(makeConnection: { [unowned self] _, callback, refcon in
            self.callback = callback
            self.refcon = refcon
            return connection
        })
        monitor.isSwitching = { [unowned self] in self.switching }
        XCTAssertTrue(monitor.start())
    }

    override func tearDown() {
        monitor.stop()
        monitor = nil
        super.tearDown()
    }

    // MARK: Held action keys

    /// A Q pressed and released mid-session never reaches the app at all.
    func testAReleaseDuringItsSessionIsConsumed() {
        switching = true
        XCTAssertFalse(reachesApps(.keyDown, qKey(down: true, flags: .maskCommand)))
        XCTAssertFalse(reachesApps(.keyUp, qKey(down: false)))
    }

    /// The pairing rule the bookkeeping exists for: a Q pressed mid-session was
    /// swallowed, so its release is swallowed too, even after the session ended.
    func testAReleaseOutlivingItsSessionIsStillConsumed() {
        switching = true
        XCTAssertFalse(reachesApps(.keyDown, qKey(down: true, flags: .maskCommand)))
        switching = false

        XCTAssertFalse(reachesApps(.keyUp, qKey(down: false)))
    }

    /// The release of a swallowed press can bypass the tap (it was timed out
    /// or rebuilt meanwhile). The next Q typed into another app reaches that
    /// app, so its release must reach it too, or the app sees Q held forever.
    func testAPressTheAppSeesGetsItsReleaseEvenAfterALostOne() {
        switching = true
        XCTAssertFalse(reachesApps(.keyDown, qKey(down: true, flags: .maskCommand)))
        switching = false
        // Q's release never came through the tap.

        XCTAssertTrue(reachesApps(.keyDown, qKey(down: true)))
        XCTAssertTrue(reachesApps(.keyUp, qKey(down: false)),
                        "the app saw this press, so it must see the release")
    }

    /// While the tap is off (Pause Zap), releases go straight to apps and never
    /// clear the record, so a press-then-pause must not swallow a later release.
    func testDisablingTheTapForgetsHeldKeys() {
        switching = true
        XCTAssertFalse(reachesApps(.keyDown, qKey(down: true, flags: .maskCommand)))
        switching = false

        monitor.setEnabled(false)
        // Q released while paused, then pressed again, also while paused.
        monitor.setEnabled(true)

        XCTAssertTrue(reachesApps(.keyUp, qKey(down: false)))
    }

    // MARK: Re-enabling after the system disables the tap

    func testASystemDisableReEnablesAnActiveTap() {
        connection.isEnabled = false   // what macOS does on a slow callback

        reachesApps(.tapDisabledByTimeout, CGEvent(source: nil)!)

        XCTAssertTrue(connection.isEnabled)
    }

    /// A disable notification already queued when the user paused Zap must not
    /// switch the tap back on: ⌘-Tab would then be swallowed with no switcher.
    func testASystemDisableLeavesADeliberatelyDisabledTapOff() {
        var reEnableReports = 0
        monitor.onTapReEnabled = { reEnableReports += 1 }
        monitor.setEnabled(false)

        reachesApps(.tapDisabledByTimeout, CGEvent(source: nil)!)
        reachesApps(.tapDisabledByUserInput, CGEvent(source: nil)!)

        XCTAssertFalse(connection.isEnabled)
        XCTAssertEqual(reEnableReports, 0)
    }

    // MARK: Helpers

    /// Feeds `event` to the tap and reports whether it passes on to apps
    /// (`false`: the tap consumed it). Answers a Bool rather than the
    /// unretained event, which would outlive the temporary it points at.
    @discardableResult
    private func reachesApps(_ type: CGEventType, _ event: CGEvent) -> Bool {
        withExtendedLifetime(event) {
            callback(OpaquePointer(bitPattern: 1)!, type, event, refcon) != nil
        }
    }

    private func qKey(down: Bool, flags: CGEventFlags = []) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: Self.qKeyCode, keyDown: down)!
        event.flags = flags
        let text = Array("q".utf16)
        event.keyboardSetUnicodeString(stringLength: text.count, unicodeString: text)
        return event
    }
}
