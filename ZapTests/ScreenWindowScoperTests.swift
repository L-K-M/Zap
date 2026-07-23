import XCTest
import CoreGraphics
@testable import Zap

/// Tests the geometry and parsing that map Quartz windows to the display they live
/// on, so the switcher can scope its app list per screen.
final class ScreenWindowScoperTests: XCTestCase {

    func testWindowSnapshotIsNotLimitedToOnscreenWindows() {
        // `.optionAll` is zero, so the contract is locked by the absence of the
        // mutually exclusive `.optionOnScreenOnly` bit.
        XCTAssertFalse(ScreenWindowScoper.windowListOptions.contains(.optionOnScreenOnly))
        XCTAssertTrue(ScreenWindowScoper.windowListOptions.contains(.excludeDesktopElements))
    }

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
    /// describe a normal, document-sized window. Optional fields are included only
    /// when provided.
    private func entry(pid: pid_t = 42, layer: Int = 0,
                       x: Double = 0, y: Double = 0,
                       width: Double = 800, height: Double = 600,
                       alpha: Double = 1,
                       windowID: CGWindowID? = nil) -> [String: Any] {
        var info: [String: Any] = [
            kCGWindowOwnerPID as String: NSNumber(value: pid),
            kCGWindowLayer as String: NSNumber(value: layer),
            kCGWindowAlpha as String: NSNumber(value: alpha),
            kCGWindowBounds as String: [
                "X": NSNumber(value: x), "Y": NSNumber(value: y),
                "Width": NSNumber(value: width), "Height": NSNumber(value: height),
            ],
        ]
        if let windowID { info[kCGWindowNumber as String] = NSNumber(value: windowID) }
        return info
    }

    func testNormalWindowParses() {
        let window = ScreenWindowScoper.scopedWindow(from: entry())
        XCTAssertEqual(window, ScreenWindowScoper.ScopedWindow(
            pid: 42, cgBounds: CGRect(x: 0, y: 0, width: 800, height: 600)))
    }

    func testWindowNumberParses() {
        let window = ScreenWindowScoper.scopedWindow(from: entry(windowID: 101))
        XCTAssertEqual(window, ScreenWindowScoper.ScopedWindow(
            pid: 42, cgBounds: CGRect(x: 0, y: 0, width: 800, height: 600),
            windowID: 101))
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

    // MARK: All-Space membership

    func testRegularWindowOnInactiveSpaceIsIncluded() {
        let windows = [
            ScreenWindowScoper.ScopedWindow(
                pid: 1, cgBounds: CGRect(x: 100, y: 100, width: 400, height: 400),
                windowID: 101),
        ]
        let pids = ScreenWindowScoper.pids(
            for: windows, targetScreenIndex: 0, screenFrames: screens, primaryHeight: 1000,
            includingFullScreenFromOtherSpaces: false, inactiveFullscreenWindowIDs: [999])
        XCTAssertEqual(pids, [1])
    }

    func testFullScreenWindowsOnInactiveSpacesCanBeExcluded() {
        // Includes a full-display window and both halves of a Split View pair. Space
        // membership, not geometry, classifies all three consistently.
        let windows = [
            ScreenWindowScoper.ScopedWindow(
                pid: 1, cgBounds: CGRect(x: 100, y: 100, width: 400, height: 400),
                windowID: 101),
            ScreenWindowScoper.ScopedWindow(
                pid: 2, cgBounds: CGRect(x: 0, y: 0, width: 1000, height: 1000),
                windowID: 102),
            ScreenWindowScoper.ScopedWindow(
                pid: 3, cgBounds: CGRect(x: 0, y: 0, width: 500, height: 1000),
                windowID: 103),
            ScreenWindowScoper.ScopedWindow(
                pid: 4, cgBounds: CGRect(x: 500, y: 0, width: 500, height: 1000),
                windowID: 104),
        ]
        let pids = ScreenWindowScoper.pids(
            for: windows, targetScreenIndex: 0, screenFrames: screens, primaryHeight: 1000,
            includingFullScreenFromOtherSpaces: false,
            inactiveFullscreenWindowIDs: [102, 103, 104])
        XCTAssertEqual(pids, [1])
    }

    func testCurrentFullScreenAndSplitViewWindowsAreIncluded() {
        let windows = [
            ScreenWindowScoper.ScopedWindow(
                pid: 1, cgBounds: CGRect(x: 0, y: 0, width: 500, height: 1000),
                windowID: 101),
            ScreenWindowScoper.ScopedWindow(
                pid: 2, cgBounds: CGRect(x: 500, y: 0, width: 500, height: 1000),
                windowID: 102),
        ]
        let pids = ScreenWindowScoper.pids(
            for: windows, targetScreenIndex: 0, screenFrames: screens, primaryHeight: 1000,
            includingFullScreenFromOtherSpaces: false, inactiveFullscreenWindowIDs: [])
        XCTAssertEqual(pids, [1, 2])
    }

    func testFullScreenWindowsOnInactiveSpacesIncludedWhenEnabled() {
        let windows = [
            ScreenWindowScoper.ScopedWindow(
                pid: 1, cgBounds: CGRect(x: 0, y: 0, width: 500, height: 1000),
                windowID: 101),
            ScreenWindowScoper.ScopedWindow(
                pid: 2, cgBounds: CGRect(x: 500, y: 0, width: 500, height: 1000),
                windowID: 102),
        ]
        let pids = ScreenWindowScoper.pids(
            for: windows, targetScreenIndex: 0, screenFrames: screens, primaryHeight: 1000,
            includingFullScreenFromOtherSpaces: true,
            inactiveFullscreenWindowIDs: [101, 102])
        XCTAssertEqual(pids, [1, 2])
    }

    func testAppWithRegularWindowRemainsWhenItsFullScreenWindowIsExcluded() {
        let windows = [
            ScreenWindowScoper.ScopedWindow(
                pid: 1, cgBounds: CGRect(x: 100, y: 100, width: 400, height: 400),
                windowID: 101),
            ScreenWindowScoper.ScopedWindow(
                pid: 1, cgBounds: CGRect(x: 0, y: 0, width: 1000, height: 1000),
                windowID: 102),
        ]
        let pids = ScreenWindowScoper.pids(
            for: windows, targetScreenIndex: 0, screenFrames: screens, primaryHeight: 1000,
            includingFullScreenFromOtherSpaces: false,
            inactiveFullscreenWindowIDs: [102])
        XCTAssertEqual(pids, [1])
    }

    func testUnavailableFullScreenMembershipFailsOpen() {
        let windows = [
            ScreenWindowScoper.ScopedWindow(
                pid: 1, cgBounds: CGRect(x: 0, y: 0, width: 1000, height: 1000),
                windowID: 101),
        ]
        let pids = ScreenWindowScoper.pids(
            for: windows, targetScreenIndex: 0, screenFrames: screens, primaryHeight: 1000,
            includingFullScreenFromOtherSpaces: false,
            inactiveFullscreenWindowIDs: nil)
        XCTAssertEqual(pids, [1])
    }

    func testMissingWindowIDFailsOpen() {
        let windows = [
            ScreenWindowScoper.ScopedWindow(
                pid: 1, cgBounds: CGRect(x: 0, y: 0, width: 1000, height: 1000),
                windowID: nil),
        ]
        let pids = ScreenWindowScoper.pids(
            for: windows, targetScreenIndex: 0, screenFrames: screens, primaryHeight: 1000,
            includingFullScreenFromOtherSpaces: false,
            inactiveFullscreenWindowIDs: [102])
        XCTAssertEqual(pids, [1])
    }

    func testSkyLightNonmemberIsKeptEvenWhenWindowFillsDisplay() {
        // A maximized ordinary window must not be inferred to be full-screen when
        // authoritative Space membership says otherwise.
        let windows = [
            ScreenWindowScoper.ScopedWindow(
                pid: 1, cgBounds: CGRect(x: 0, y: 0, width: 1000, height: 1000),
                windowID: 101),
        ]
        let pids = ScreenWindowScoper.pids(
            for: windows, targetScreenIndex: 0, screenFrames: screens, primaryHeight: 1000,
            includingFullScreenFromOtherSpaces: false,
            inactiveFullscreenWindowIDs: [999])
        XCTAssertEqual(pids, [1])
    }

    // MARK: SkyLight full-screen Space parsing

    func testSpaceGroupsKeepCurrentFullScreenSpaceRetained() {
        let displays: [[String: Any]] = [
            ["Current Space": ["id64": NSNumber(value: 7)], "Spaces": [
                ["id64": NSNumber(value: 4), "type": NSNumber(value: 0)],   // user desktop
                ["id64": NSNumber(value: 7), "type": NSNumber(value: 4)],   // current full-screen
                ["id64": NSNumber(value: 8), "type": NSNumber(value: 4)],   // inactive full-screen
            ]],
            ["Current Space": ["id64": NSNumber(value: 11)], "Spaces": [
                ["id64": NSNumber(value: 11), "type": NSNumber(value: 0)],  // current desktop
                ["id64": NSNumber(value: 12), "type": NSNumber(value: 4)],  // full-screen (Split View)
                ["id64": NSNumber(value: 13), "type": NSNumber(value: 2)],  // system
            ]],
        ]
        XCTAssertEqual(
            FullscreenSpaceWindows.spaceGroups(fromDisplaySpaces: displays),
            FullscreenSpaceWindows.SpaceGroups(
                inactiveFullscreen: [8, 12], retained: [4, 7, 11, 13]))
    }

    func testSpaceGroupsRejectMalformedTopology() {
        let displays: [[String: Any]] = [
            ["Spaces": [
                ["id64": NSNumber(value: 7), "type": NSNumber(value: 4)],
            ]], // no Current Space
        ]
        XCTAssertNil(FullscreenSpaceWindows.spaceGroups(fromDisplaySpaces: displays))
    }

    func testSpaceGroupsRejectCurrentSpaceMissingFromSpaceList() {
        let displays: [[String: Any]] = [
            ["Current Space": ["id64": NSNumber(value: 99)], "Spaces": [
                ["id64": NSNumber(value: 7), "type": NSNumber(value: 4)],
            ]],
        ]
        XCTAssertNil(FullscreenSpaceWindows.spaceGroups(fromDisplaySpaces: displays))
    }

    func testSpaceGroupsRejectNonIntegralAndNegativeIDs() {
        let fractional: [[String: Any]] = [
            ["Current Space": ["id64": NSNumber(value: 7.5)], "Spaces": [
                ["id64": NSNumber(value: 7.5), "type": NSNumber(value: 4)],
            ]],
        ]
        let negative: [[String: Any]] = [
            ["Current Space": ["id64": NSNumber(value: -1)], "Spaces": [
                ["id64": NSNumber(value: -1), "type": NSNumber(value: 4)],
            ]],
        ]
        XCTAssertNil(FullscreenSpaceWindows.spaceGroups(fromDisplaySpaces: fractional))
        XCTAssertNil(FullscreenSpaceWindows.spaceGroups(fromDisplaySpaces: negative))
    }

    func testWindowIDParsingRejectsMalformedOrOutOfRangeValues() {
        XCTAssertEqual(FullscreenSpaceWindows.windowIDs(
            from: [NSNumber(value: 101), NSNumber(value: 102)]), [101, 102])
        XCTAssertNil(FullscreenSpaceWindows.windowIDs(from: [NSNumber(value: 1.5)]))
        XCTAssertNil(FullscreenSpaceWindows.windowIDs(from: [NSNumber(value: -1)]))
        XCTAssertNil(FullscreenSpaceWindows.windowIDs(
            from: [NSNumber(value: UInt64(CGWindowID.max) + 1)]))
        XCTAssertNil(FullscreenSpaceWindows.windowIDs(from: ["101"]))
    }

    func testStickyWindowsAreNotExclusiveToInactiveFullScreenSpaces() {
        let exclusive = FullscreenSpaceWindows.exclusiveWindowIDs(
            in: [101, 102], excluding: [102, 103])
        XCTAssertEqual(exclusive, [101])
    }
}
