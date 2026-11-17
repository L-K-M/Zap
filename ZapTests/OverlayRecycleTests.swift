import AppKit
import XCTest
@testable import Zap

final class OverlayRecycleTests: XCTestCase {

    @MainActor
    func testAgedOutWindowIsRecycledWhileHidden() throws {
        let clock = FakeClock()
        try withOverlay(clock: clock) { fixture in
            let original = try fixture.overlayWindow()
            clock.advance(by: 31 * 60)
            fixture.controller.hide()

            let recycled = spinRunLoop(for: 2, until: {
                fixture.overlayWindows.contains { $0 !== original }
            })
            XCTAssertTrue(recycled, "An aged-out window should be replaced while hidden")
            let replacement = try XCTUnwrap(fixture.overlayWindows.first { $0 !== original })
            XCTAssertFalse(replacement === original)
        }
    }

    /// After a hidden recycle the replacement is watched too, so a long idle
    /// spell can't age it out and put the rebuild back on the next ⌘-Tab.
    @MainActor
    func testARecycleWhileHiddenKeepsWatchingTheReplacement() throws {
        let clock = FakeClock()
        try withOverlay(clock: clock) { fixture in
            let original = try fixture.overlayWindow()
            clock.advance(by: 31 * 60)
            fixture.controller.hide()

            XCTAssertTrue(spinRunLoop(for: 2, until: {
                fixture.overlayWindows.contains { $0 !== original }
            }))
            XCTAssertTrue(fixture.controller.hasPendingRecycle)
        }
    }

    @MainActor
    func testYoungWindowIsNotRecycledWhileHidden() throws {
        let clock = FakeClock()
        try withOverlay(clock: clock) { fixture in
            let original = try fixture.overlayWindow()
            clock.advance(by: 5 * 60)
            fixture.controller.hide()

            spinRunLoop(for: 0.5)
            XCTAssertTrue(fixture.overlayWindows.contains { $0 === original },
                          "A young window should still be the overlay window")
            XCTAssertEqual(fixture.overlayWindows.count, 1,
                           "A young window must not be replaced while hidden")
        }
    }

    @MainActor
    func testReplacedWindowIsClosed() throws {
        let clock = FakeClock()
        try withOverlay(clock: clock) { fixture in
            let original = try fixture.overlayWindow()
            let closeRecorder = CloseRecorder()
            original.delegate = closeRecorder
            clock.advance(by: 31 * 60)
            fixture.controller.hide()

            let closed = spinRunLoop(for: 2, until: { closeRecorder.didClose })
            XCTAssertTrue(closed, "The replaced window should be closed")
            XCTAssertTrue(fixture.overlayWindows.contains { $0 !== original },
                          "A replacement window should exist")
        }
    }

    // MARK: Helpers

    @MainActor
    private func withOverlay(clock: FakeClock, check: (Fixture) throws -> Void) throws {
        let suite = "zap-overlay-recycle-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        let fixture = try Fixture(preferences: preferences, clock: clock)
        defer { fixture.controller.hide() }
        fixture.show()
        try check(fixture)
    }

    /// Spins the main run loop for up to `duration`, stopping as soon as
    /// `condition` holds. Returns whether it did.
    @MainActor
    @discardableResult
    private func spinRunLoop(for duration: TimeInterval,
                             until condition: () -> Bool = { false }) -> Bool {
        let deadline = Date().addingTimeInterval(duration)
        while !condition() {
            let next = Date().addingTimeInterval(0.01)
            guard next < deadline else { return false }
            RunLoop.main.run(until: next)
        }
        return true
    }

    @MainActor
    private final class Fixture {
        let controller: OverlayWindowController
        let clock: FakeClock
        let screen: NSScreen
        private let existing: Set<ObjectIdentifier>

        init(preferences: Preferences, clock: FakeClock) throws {
            self.clock = clock
            self.screen = try XCTUnwrap(NSScreen.main)
            existing = Set(NSApp.windows.map(ObjectIdentifier.init))
            controller = OverlayWindowController(
                preferences: preferences,
                isWindowOnscreen: { _ in true },
                scheduleVisibilityCheck: { _ in },
                now: { [clock] in clock.current }
            )
        }

        var overlayWindows: [NSWindow] {
            NSApp.windows.filter { !existing.contains(ObjectIdentifier($0)) }
        }

        func overlayWindow() throws -> NSWindow {
            try XCTUnwrap(overlayWindows.first)
        }

        func show() {
            controller.show(apps: [
                AppInfo(bundleIdentifier: "test.one", name: "One", processIdentifier: 41),
                AppInfo(bundleIdentifier: "test.two", name: "Two", processIdentifier: 42)
            ], selectedIndex: 0, on: screen)
        }
    }

    @MainActor
    private final class FakeClock {
        var current = Date()

        func advance(by interval: TimeInterval) {
            current = current.addingTimeInterval(interval)
        }
    }

    private final class CloseRecorder: NSObject, NSWindowDelegate {
        private(set) var didClose = false

        func windowWillClose(_ notification: Notification) {
            didClose = true
        }
    }
}
