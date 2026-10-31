import CoreGraphics
import XCTest
@testable import Zap

final class EventTapLifecycleTests: XCTestCase {
    private final class Connection: EventTapConnection {
        var isValid = true
        var isEnabled = false
        var registeredEvents: CGEventMask?
        private(set) var invalidations = 0

        init(events: CGEventMask?) { registeredEvents = events }
        func setEnabled(_ enabled: Bool) { isEnabled = enabled }
        func invalidate() {
            invalidations += 1
            isValid = false
            isEnabled = false
        }
    }

    func testFlagsOnlyRegistrationIsRejectedAndDisposed() {
        let connection = Connection(events: 1 << CGEventType.flagsChanged.rawValue)
        let monitor = EventTapMonitor(makeConnection: { _, _, _ in connection })
        defer { monitor.stop() }

        XCTAssertFalse(monitor.start(), "A valid modifier-only tap cannot intercept Cmd-Tab")
        XCTAssertFalse(monitor.isRunning)
        XCTAssertEqual(connection.invalidations, 1)
    }

    func testNextAttemptCanRecoverAfterAnIncompleteRegistration() {
        let incomplete = Connection(events: 1 << CGEventType.flagsChanged.rawValue)
        let complete = Connection(events: EventTapMonitor.requiredEvents)
        var attempts = 0
        let monitor = EventTapMonitor(makeConnection: { events, _, _ in
            XCTAssertEqual(events, EventTapMonitor.requiredEvents)
            attempts += 1
            return attempts == 1 ? incomplete : complete
        })
        defer { monitor.stop() }

        XCTAssertFalse(monitor.start())
        XCTAssertTrue(monitor.start())
        XCTAssertTrue(monitor.isReady)
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(incomplete.invalidations, 1)

        XCTAssertTrue(monitor.start())
        XCTAssertEqual(attempts, 2, "A healthy registration must be reused")
    }

    func testUnverifiableRegistrationIsRejected() {
        let connection = Connection(events: nil)
        let monitor = EventTapMonitor(makeConnection: { _, _, _ in connection })
        defer { monitor.stop() }

        XCTAssertFalse(monitor.start())
        XCTAssertEqual(connection.invalidations, 1)
    }

    func testEachRequiredEventMustBeRegistered() {
        for event in [CGEventType.keyDown, .keyUp, .flagsChanged] {
            let events = EventTapMonitor.requiredEvents & ~CGEventMask(1 << event.rawValue)
            let connection = Connection(events: events)
            let monitor = EventTapMonitor(makeConnection: { _, _, _ in connection })
            XCTAssertFalse(monitor.start(), "Missing \(event) must reject the registration")
            XCTAssertEqual(connection.invalidations, 1)
            monitor.stop()
        }
    }

    func testRetainedRegistrationLosingKeyboardEventsIsReplaced() {
        let original = Connection(events: EventTapMonitor.requiredEvents)
        let replacement = Connection(events: EventTapMonitor.requiredEvents)
        var attempts = 0
        let monitor = EventTapMonitor(makeConnection: { _, _, _ in
            attempts += 1
            return attempts == 1 ? original : replacement
        })
        defer { monitor.stop() }

        XCTAssertTrue(monitor.start())
        original.registeredEvents = 1 << CGEventType.flagsChanged.rawValue
        XCTAssertFalse(monitor.isReady)
        XCTAssertTrue(monitor.start())
        XCTAssertEqual(original.invalidations, 1)
        XCTAssertTrue(monitor.isReady)
        XCTAssertEqual(attempts, 2)
    }

    func testInvalidRetainedConnectionIsReplaced() {
        let original = Connection(events: EventTapMonitor.requiredEvents)
        let replacement = Connection(events: EventTapMonitor.requiredEvents)
        var attempts = 0
        let monitor = EventTapMonitor(makeConnection: { _, _, _ in
            attempts += 1
            return attempts == 1 ? original : replacement
        })
        defer { monitor.stop() }

        XCTAssertTrue(monitor.start())
        original.isValid = false
        XCTAssertTrue(monitor.start())
        XCTAssertEqual(original.invalidations, 1)
        XCTAssertEqual(attempts, 2)
    }

    func testUnknownHealthDoesNotMasqueradeAsReady() {
        let connection = Connection(events: EventTapMonitor.requiredEvents)
        let monitor = EventTapMonitor(makeConnection: { _, _, _ in connection })
        defer { monitor.stop() }

        XCTAssertTrue(monitor.start())
        connection.registeredEvents = nil
        XCTAssertFalse(monitor.isReady)
    }

    func testInputRecoveryRespectsEligibilityAndHealthyHooks() {
        let retry = SwitcherController.shouldRefreshInputMode
        XCTAssertTrue(retry(false, false, true, false, false, false), "Promote fallback after access is granted")
        XCTAssertTrue(retry(false, false, true, true, false, true), "Repair an incomplete hook, ending any stranded session")
        XCTAssertTrue(retry(false, false, false, true, true, false), "Stop interception after access is revoked")
        XCTAssertFalse(retry(false, false, true, true, true, true), "Leave a healthy hook alone")
        XCTAssertFalse(retry(false, false, false, false, false, false), "Wait for Accessibility access")
        XCTAssertFalse(retry(true, false, true, false, false, false), "Respect Pause")
        XCTAssertFalse(retry(false, true, true, false, false, false), "Respect the alternate hotkey")
        XCTAssertFalse(retry(false, false, true, false, false, true), "Finish a fallback selection before retrying")
    }
}
