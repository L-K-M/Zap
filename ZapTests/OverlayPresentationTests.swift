import AppKit
import XCTest
@testable import Zap

final class OverlayPresentationTests: XCTestCase {

    @MainActor
    func testConfirmedFailedOrderingRecreatesWindowAndPreservesSelection() throws {
        try withOverlay(onscreen: false) { fixture in
            let original = try fixture.primaryWindow()
            let host = try XCTUnwrap(original.contentView?.subviews.first)
            let frame = original.frame
            fixture.controller.model.selectedIndex = 1
            fixture.controller.model.scrollOffset = 12
            fixture.controller.model.typeQuery = "test"
            fixture.controller.model.showsHelp = true
            fixture.controller.model.quittingPIDs = [42]
            let preview = NSImage(size: NSSize(width: 20, height: 20))
            let appWindow = WindowInfo(title: "Document", isMinimized: false,
                                       element: nil, cgWindowID: 123)
            fixture.controller.model.windows = [appWindow]
            fixture.controller.model.windowSelectedIndex = 0
            fixture.controller.model.windowThumbnails = [123: preview]

            try fixture.runCheck()
            XCTAssertTrue(try fixture.primaryWindow() === original,
                          "Retry ordering before replacing a native window")
            try fixture.runCheck()
            let replacement = try fixture.primaryWindow()
            XCTAssertFalse(replacement === original)
            XCTAssertTrue(replacement.contentView?.subviews.first === host)
            XCTAssertEqual(replacement.frame, frame)
            XCTAssertTrue(fixture.controller.isVisible)
            XCTAssertEqual(fixture.controller.model.apps.count, 2)
            XCTAssertEqual(fixture.controller.model.selectedIndex, 1)
            XCTAssertEqual(fixture.controller.model.scrollOffset, 12)
            XCTAssertEqual(fixture.controller.model.typeQuery, "test")
            XCTAssertTrue(fixture.controller.model.showsHelp)
            XCTAssertEqual(fixture.controller.model.quittingPIDs, [42])
            XCTAssertEqual(fixture.controller.model.windows, [appWindow])
            XCTAssertEqual(fixture.controller.model.windowSelectedIndex, 0)
            XCTAssertTrue(fixture.controller.model.windowThumbnails[123] === preview)
            try fixture.runCheck()
            XCTAssertTrue(try fixture.primaryWindow() === replacement)
            XCTAssertTrue(fixture.checks.isEmpty, "Recovery must stop after one replacement")
        }
    }

    @MainActor
    func testHealthyOrUnknownVisibilityDoesNotReplaceWindow() throws {
        for status: Bool? in [true, nil] {
            try withOverlay(onscreen: status) { fixture in
                let original = try fixture.primaryWindow()
                try fixture.runCheck()
                XCTAssertTrue(try fixture.primaryWindow() === original)
                XCTAssertTrue(fixture.checks.isEmpty)
            }
        }
    }

    @MainActor
    func testHideCancelsPendingRecovery() throws {
        try withOverlay(onscreen: false) { fixture in
            fixture.controller.hide()
            try fixture.runCheck()
            XCTAssertFalse(fixture.controller.isVisible)
            XCTAssertTrue(fixture.visibleWindows.isEmpty)
            XCTAssertTrue(fixture.checks.isEmpty)
        }
    }

    @MainActor
    func testOldCheckCannotRepairNewPresentation() throws {
        try withOverlay(onscreen: false) { fixture in
            fixture.controller.hide()
            fixture.show()
            let current = try fixture.primaryWindow()
            let count = fixture.checks.count
            try fixture.runCheck()
            XCTAssertTrue(try fixture.primaryWindow() === current)
            XCTAssertEqual(fixture.checks.count, count - 1)
        }
    }

    @MainActor
    func testOrderingRetryCanRecoverWithoutReplacement() throws {
        try withOverlay(onscreen: false) { fixture in
            let original = try fixture.primaryWindow()
            try fixture.runCheck()
            fixture.onscreen = true
            try fixture.runCheck()
            XCTAssertTrue(try fixture.primaryWindow() === original)
            XCTAssertTrue(fixture.checks.isEmpty)
        }
    }

    @MainActor
    func testWindowsCanJoinOtherApplicationsFullscreenSpaces() throws {
        try withOverlay(onscreen: true) { fixture in
            XCTAssertTrue(try fixture.primaryWindow().collectionBehavior
                .contains(.canJoinAllApplications))
        }
    }

    @MainActor
    func testFailedMirrorIsRecoveredWhenPrimaryIsHealthy() throws {
        guard NSScreen.screens.count > 1 else {
            throw XCTSkip("Mirror integration needs multiple displays")
        }
        try withOverlay(onscreen: true, allScreens: true) { fixture in
            let originals = fixture.visibleWindows
            let primary = try fixture.primaryWindow()
            let mirror = try XCTUnwrap(originals.first { $0 !== primary })
            fixture.failedWindow = mirror
            try fixture.runCheck()
            try fixture.runCheck()
            XCTAssertTrue(originals.allSatisfy { old in
                !fixture.visibleWindows.contains { $0 === old }
            })
            XCTAssertEqual(fixture.visibleWindows.count, NSScreen.screens.count)
            XCTAssertTrue(fixture.visibleWindows.allSatisfy {
                $0.collectionBehavior.contains(.canJoinAllApplications)
            })
            try fixture.runCheck()
            XCTAssertTrue(fixture.checks.isEmpty)
        }
    }

    @MainActor
    private func withOverlay(onscreen: Bool?, allScreens: Bool = false,
                             check: (Fixture) throws -> Void) throws {
        let suite = "zap-overlay-presentation-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        preferences.showOnAllScreens = allScreens
        let fixture = try Fixture(preferences: preferences, onscreen: onscreen)
        defer { fixture.controller.hide() }
        fixture.show()
        try check(fixture)
    }

    @MainActor
    private final class Fixture {
        var onscreen: Bool?
        weak var failedWindow: NSWindow?
        var checks: [() -> Void] = []
        let screen: NSScreen
        let existing: Set<ObjectIdentifier>
        var controller: OverlayWindowController!

        init(preferences: Preferences, onscreen: Bool?) throws {
            self.onscreen = onscreen
            screen = try XCTUnwrap(NSScreen.main)
            existing = Set(NSApp.windows.map(ObjectIdentifier.init))
            controller = OverlayWindowController(preferences: preferences,
                isWindowOnscreen: { [weak self] window in
                    guard let self else { return nil }
                    return window === self.failedWindow ? false : self.onscreen
                },
                scheduleVisibilityCheck: { [weak self] in self?.checks.append($0) })
        }

        var visibleWindows: [NSWindow] {
            NSApp.windows.filter { !existing.contains(ObjectIdentifier($0)) && $0.isVisible }
        }

        func primaryWindow() throws -> NSWindow {
            try XCTUnwrap(visibleWindows.first { $0.screen === screen })
        }

        func show() {
            controller.show(apps: [
                AppInfo(bundleIdentifier: "test.one", name: "One", processIdentifier: 41),
                AppInfo(bundleIdentifier: "test.two", name: "Two", processIdentifier: 42)
            ], selectedIndex: 0, on: screen)
        }

        func runCheck() throws {
            XCTAssertFalse(checks.isEmpty, "A shown window needs a settled visibility check")
            guard !checks.isEmpty else { return }
            checks.removeFirst()()
        }
    }
}
