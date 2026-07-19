import XCTest
import CoreGraphics
@testable import Zap

/// Tests the geometry and parsing that map Quartz windows to the display they live
/// on, so the switcher can scope its app list per screen.
final class ScreenWindowScoperTests: XCTestCase {

    // MARK: Coordinate flip

    func testAppKitRectFlipsYFromTopLeftToBottomLeft() {
        // A window at the very top-left of a 1000-tall primary display.
        let cg = CGRect(x: 0, y: 0, width: 100, height: 100)
        let appKit = ScreenWindowScoper.appKitRect(fromCG: cg, primaryHeight: 1000)
        XCTAssertEqual(appKit, CGRect(x: 0, y: 900, width: 100, height: 100))
    }

    func testAppKitRectKeepsXAndSize() {
        let cg = CGRect(x: 250, y: 300, width: 400, height: 200)
        let appKit = ScreenWindowScoper.appKitRect(fromCG: cg, primaryHeight: 1080)
        XCTAssertEqual(appKit, CGRect(x: 250, y: 1080 - 300 - 200, width: 400, height: 200))
    }

    // MARK: Dominant screen

    private let screens = [
        CGRect(x: 0, y: 0, width: 1000, height: 1000),       // index 0
        CGRect(x: 1000, y: 0, width: 1000, height: 1000),    // index 1, to the right
    ]

    func testWindowFullyOnFirstScreen() {
        let window = CGRect(x: 100, y: 100, width: 200, height: 200)
        XCTAssertEqual(ScreenWindowScoper.dominantScreenIndex(windowFrame: window, screenFrames: screens), 0)
    }

    func testWindowFullyOnSecondScreen() {
        let window = CGRect(x: 1200, y: 100, width: 200, height: 200)
        XCTAssertEqual(ScreenWindowScoper.dominantScreenIndex(windowFrame: window, screenFrames: screens), 1)
    }

    func testStraddlingWindowGoesToScreenHoldingMostOfIt() {
        // 50px on screen 0, 150px on screen 1 → screen 1 wins.
        let window = CGRect(x: 950, y: 100, width: 200, height: 200)
        XCTAssertEqual(ScreenWindowScoper.dominantScreenIndex(windowFrame: window, screenFrames: screens), 1)
    }

    func testWindowOffAllScreensIsNil() {
        let window = CGRect(x: 5000, y: 5000, width: 100, height: 100)
        XCTAssertNil(ScreenWindowScoper.dominantScreenIndex(windowFrame: window, screenFrames: screens))
    }

    // MARK: PID attribution

    func testPidsAttributedToTargetScreenOnly() {
        // pid 1 on screen 0; pid 2 on screen 1; pid 3 off-screen. primaryHeight 1000.
        let windows = [
            ScreenWindowScoper.ScopedWindow(pid: 1, cgBounds: CGRect(x: 100, y: 100, width: 200, height: 200)),
            ScreenWindowScoper.ScopedWindow(pid: 2, cgBounds: CGRect(x: 1200, y: 100, width: 200, height: 200)),
            ScreenWindowScoper.ScopedWindow(pid: 3, cgBounds: CGRect(x: 5000, y: 5000, width: 100, height: 100)),
        ]
        let onScreen0 = ScreenWindowScoper.pids(for: windows, targetScreenIndex: 0,
                                                screenFrames: screens, primaryHeight: 1000)
        let onScreen1 = ScreenWindowScoper.pids(for: windows, targetScreenIndex: 1,
                                                screenFrames: screens, primaryHeight: 1000)
        XCTAssertEqual(onScreen0, [1])
        XCTAssertEqual(onScreen1, [2])
    }

    func testMultipleWindowsSameAppCollapseToOnePid() {
        let windows = [
            ScreenWindowScoper.ScopedWindow(pid: 7, cgBounds: CGRect(x: 100, y: 100, width: 200, height: 200)),
            ScreenWindowScoper.ScopedWindow(pid: 7, cgBounds: CGRect(x: 400, y: 100, width: 200, height: 200)),
        ]
        let pids = ScreenWindowScoper.pids(for: windows, targetScreenIndex: 0,
                                           screenFrames: screens, primaryHeight: 1000)
        XCTAssertEqual(pids, [7])
    }

    // MARK: Window-list entry parsing

    /// A Quartz window-list entry, mirroring `CGWindowListCopyWindowInfo`. Defaults
    /// describe a normal, document-sized window. `onscreen` adds `kCGWindowIsOnscreen`
    /// only when provided, so the on-screen parsing tests stay unaffected.
    private func entry(pid: pid_t = 42, layer: Int = 0,
                       x: Double = 0, y: Double = 0,
                       width: Double = 800, height: Double = 600,
                       alpha: Double = 1, onscreen: Bool? = nil) -> [String: Any] {
        var info: [String: Any] = [
            kCGWindowOwnerPID as String: NSNumber(value: pid),
            kCGWindowLayer as String: NSNumber(value: layer),
            kCGWindowAlpha as String: NSNumber(value: alpha),
            kCGWindowBounds as String: [
                "X": NSNumber(value: x), "Y": NSNumber(value: y),
                "Width": NSNumber(value: width), "Height": NSNumber(value: height),
            ],
        ]
        if let onscreen { info[kCGWindowIsOnscreen as String] = NSNumber(value: onscreen) }
        return info
    }

    func testNormalWindowParses() {
        let window = ScreenWindowScoper.scopedWindow(from: entry())
        XCTAssertEqual(window, ScreenWindowScoper.ScopedWindow(
            pid: 42, cgBounds: CGRect(x: 0, y: 0, width: 800, height: 600)))
    }

    func testNonNormalLayerRejected() {
        // Menus, the Dock, panels sit above the normal window layer.
        XCTAssertNil(ScreenWindowScoper.scopedWindow(from: entry(layer: 25)))
    }

    func testTinyWindowRejected() {
        XCTAssertNil(ScreenWindowScoper.scopedWindow(from: entry(width: 40, height: 40)))
    }

    func testTransparentWindowRejected() {
        XCTAssertNil(ScreenWindowScoper.scopedWindow(from: entry(alpha: 0)))
    }

    func testMissingBoundsRejected() {
        var info = entry()
        info.removeValue(forKey: kCGWindowBounds as String)
        XCTAssertNil(ScreenWindowScoper.scopedWindow(from: info))
    }

    // MARK: Off-Space full-screen windows

    func testOffSpaceWindowParsesWhenNotOnscreen() {
        // A window on another Space (e.g. full-screen) — onscreen flag false.
        let window = ScreenWindowScoper.offSpaceScopedWindow(from: entry(onscreen: false))
        XCTAssertEqual(window, ScreenWindowScoper.ScopedWindow(
            pid: 42, cgBounds: CGRect(x: 0, y: 0, width: 800, height: 600)))
    }

    func testOffSpaceWindowParsesWhenOnscreenFlagAbsent() {
        // No onscreen flag → treat as off-Space; the on-screen pass owns on-screen ones.
        XCTAssertNotNil(ScreenWindowScoper.offSpaceScopedWindow(from: entry(onscreen: nil)))
    }

    func testOnscreenWindowRejectedFromOffSpacePass() {
        // Already counted by the on-screen pass; don't double-handle it here.
        XCTAssertNil(ScreenWindowScoper.offSpaceScopedWindow(from: entry(onscreen: true)))
    }

    func testTinyOffSpaceWindowRejected() {
        // The off-Space pass inherits `scopedWindow`'s minimum-size filter.
        XCTAssertNil(ScreenWindowScoper.offSpaceScopedWindow(from: entry(width: 40, height: 40, onscreen: false)))
    }

    // MARK: Full-screen coverage

    func testFillsScreenTrueWhenWindowCoversDisplay() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        XCTAssertTrue(ScreenWindowScoper.fillsScreen(windowFrame: screen, screenFrame: screen))
    }

    func testFillsScreenTrueWhenWindowOverhangsDisplay() {
        // Full-screen windows can overhang the menu-bar area; still counts.
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let window = CGRect(x: -10, y: -10, width: 1020, height: 1020)
        XCTAssertTrue(ScreenWindowScoper.fillsScreen(windowFrame: window, screenFrame: screen))
    }

    func testFillsScreenFalseForPartialWindow() {
        // A window covering ~36% of the display is not full-screen.
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let window = CGRect(x: 0, y: 0, width: 600, height: 600)
        XCTAssertFalse(ScreenWindowScoper.fillsScreen(windowFrame: window, screenFrame: screen))
    }

    func testFullScreenPidsKeepOnlyDisplayFillingWindowsOnTarget() {
        // pid 1 fills screen 0 (full-screen); pid 2 has a small window on screen 0;
        // pid 3 fills screen 1. Target screen 0 ⇒ only pid 1. primaryHeight 1000.
        let windows = [
            ScreenWindowScoper.ScopedWindow(pid: 1, cgBounds: CGRect(x: 0, y: 0, width: 1000, height: 1000)),
            ScreenWindowScoper.ScopedWindow(pid: 2, cgBounds: CGRect(x: 100, y: 100, width: 200, height: 200)),
            ScreenWindowScoper.ScopedWindow(pid: 3, cgBounds: CGRect(x: 1000, y: 0, width: 1000, height: 1000)),
        ]
        let onScreen0 = ScreenWindowScoper.fullScreenPids(for: windows, targetScreenIndex: 0,
                                                          screenFrames: screens, primaryHeight: 1000)
        let onScreen1 = ScreenWindowScoper.fullScreenPids(for: windows, targetScreenIndex: 1,
                                                          screenFrames: screens, primaryHeight: 1000)
        XCTAssertEqual(onScreen0, [1])
        XCTAssertEqual(onScreen1, [3])
    }

    // MARK: Split View (tiled full-screen)

    func testSplitViewTilesIncludedWhenSkyLightReportsFullScreenSpace() {
        // Two tiled windows on screen 0, each half the display: neither passes the
        // "fills the screen" test, but SkyLight places both on a full-screen Space.
        let windows = [
            ScreenWindowScoper.ScopedWindow(pid: 1, cgBounds: CGRect(x: 0, y: 0, width: 500, height: 1000), windowID: 101),
            ScreenWindowScoper.ScopedWindow(pid: 2, cgBounds: CGRect(x: 500, y: 0, width: 500, height: 1000), windowID: 102),
        ]
        let pids = ScreenWindowScoper.fullScreenPids(for: windows, fullscreenWindowIDs: [101, 102],
                                                     targetScreenIndex: 0,
                                                     screenFrames: screens, primaryHeight: 1000)
        XCTAssertEqual(pids, [1, 2])
    }

    func testSplitViewTileOnOtherDisplayExcluded() {
        // pid 1's tile is on screen 1; targeting screen 0 must not pick it up even
        // though SkyLight lists its window on a full-screen Space.
        let windows = [
            ScreenWindowScoper.ScopedWindow(pid: 1, cgBounds: CGRect(x: 1000, y: 0, width: 500, height: 1000), windowID: 101),
        ]
        let pids = ScreenWindowScoper.fullScreenPids(for: windows, fullscreenWindowIDs: [101],
                                                     targetScreenIndex: 0,
                                                     screenFrames: screens, primaryHeight: 1000)
        XCTAssertTrue(pids.isEmpty)
    }

    func testPartialWindowNotOnFullScreenSpaceExcluded() {
        // SkyLight answered (non-nil set) but doesn't list this half-size window —
        // an ordinary window parked on another Space stays out of the scoped list.
        let windows = [
            ScreenWindowScoper.ScopedWindow(pid: 1, cgBounds: CGRect(x: 0, y: 0, width: 500, height: 1000), windowID: 101),
        ]
        let pids = ScreenWindowScoper.fullScreenPids(for: windows, fullscreenWindowIDs: [999],
                                                     targetScreenIndex: 0,
                                                     screenFrames: screens, primaryHeight: 1000)
        XCTAssertTrue(pids.isEmpty)
    }

    func testNilFullScreenWindowIDsFallsBackToGeometry() {
        // SkyLight unavailable: a display-filling window still counts, a tiled one doesn't.
        let windows = [
            ScreenWindowScoper.ScopedWindow(pid: 1, cgBounds: CGRect(x: 0, y: 0, width: 1000, height: 1000), windowID: 101),
            ScreenWindowScoper.ScopedWindow(pid: 2, cgBounds: CGRect(x: 0, y: 0, width: 500, height: 1000), windowID: 102),
        ]
        let pids = ScreenWindowScoper.fullScreenPids(for: windows, fullscreenWindowIDs: nil,
                                                     targetScreenIndex: 0,
                                                     screenFrames: screens, primaryHeight: 1000)
        XCTAssertEqual(pids, [1])
    }

    // MARK: SkyLight full-screen Space parsing

    func testFullscreenSpaceIDsKeepOnlyFullScreenSpaces() {
        let displays: [[String: Any]] = [
            ["Spaces": [
                ["id64": NSNumber(value: 4), "type": NSNumber(value: 0)],   // user desktop
                ["id64": NSNumber(value: 7), "type": NSNumber(value: 4)],   // full-screen
            ]],
            ["Spaces": [
                ["id64": NSNumber(value: 12), "type": NSNumber(value: 4)],  // full-screen (Split View)
                ["id64": NSNumber(value: 13), "type": NSNumber(value: 2)],  // system
            ]],
        ]
        XCTAssertEqual(FullscreenSpaceWindows.fullscreenSpaceIDs(fromDisplaySpaces: displays), [7, 12])
    }

    func testFullscreenSpaceIDsTolerateMalformedEntries() {
        let displays: [[String: Any]] = [
            [:],                                        // no Spaces key
            ["Spaces": [["type": NSNumber(value: 4)]]], // full-screen but no id64
        ]
        XCTAssertTrue(FullscreenSpaceWindows.fullscreenSpaceIDs(fromDisplaySpaces: displays).isEmpty)
    }
}
