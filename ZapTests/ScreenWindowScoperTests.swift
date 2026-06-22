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
    /// describe a normal, document-sized window.
    private func entry(pid: pid_t = 42, layer: Int = 0,
                       x: Double = 0, y: Double = 0,
                       width: Double = 800, height: Double = 600,
                       alpha: Double = 1) -> [String: Any] {
        [
            kCGWindowOwnerPID as String: NSNumber(value: pid),
            kCGWindowLayer as String: NSNumber(value: layer),
            kCGWindowAlpha as String: NSNumber(value: alpha),
            kCGWindowBounds as String: [
                "X": NSNumber(value: x), "Y": NSNumber(value: y),
                "Width": NSNumber(value: width), "Height": NSNumber(value: height),
            ],
        ]
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
}
