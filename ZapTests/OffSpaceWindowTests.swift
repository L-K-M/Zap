import XCTest
import CoreGraphics
@testable import Zap

/// Tests the filter that decides which Quartz window-list entries are backfilled as
/// off-Space windows (e.g. full-screen windows on another desktop) when the
/// Accessibility API omits them.
final class OffSpaceWindowTests: XCTestCase {

    /// A Quartz window-list entry, mirroring `CGWindowListCopyWindowInfo` (CFNumbers
    /// bridged to `NSNumber`). Defaults describe a real off-Space document window.
    private func entry(pid: pid_t = 42,
                       layer: Int = 0,
                       onscreen: Bool? = false,
                       width: Double = 1440,
                       height: Double = 900,
                       alpha: Double = 1,
                       number: UInt32 = 99,
                       name: String? = "Project") -> [String: Any] {
        var info: [String: Any] = [
            kCGWindowOwnerPID as String: NSNumber(value: pid),
            kCGWindowLayer as String: NSNumber(value: layer),
            kCGWindowNumber as String: NSNumber(value: number),
            kCGWindowAlpha as String: NSNumber(value: alpha),
            kCGWindowBounds as String: [
                "X": NSNumber(value: 0.0), "Y": NSNumber(value: 0.0),
                "Width": NSNumber(value: width), "Height": NSNumber(value: height),
            ],
        ]
        if let onscreen { info[kCGWindowIsOnscreen as String] = NSNumber(value: onscreen) }
        if let name { info[kCGWindowName as String] = name }
        return info
    }

    func testOffSpaceDocumentWindowIsIncluded() {
        let window = WindowEnumerator.offSpaceWindowInfo(from: entry(), pid: 42)
        XCTAssertNotNil(window)
        XCTAssertEqual(window?.cgWindowID, 99)
        XCTAssertEqual(window?.title, "Project")
        XCTAssertNil(window?.element)          // no AX element for Quartz-only windows
        XCTAssertFalse(window?.isMinimized ?? true)
    }

    func testOnscreenWindowIsExcluded() {
        // On the current Space — AX already lists it, so don't double-add it.
        XCTAssertNil(WindowEnumerator.offSpaceWindowInfo(from: entry(onscreen: true), pid: 42))
    }

    func testMissingOnscreenFlagIsTreatedAsOffSpace() {
        XCTAssertNil(entry(onscreen: nil)[kCGWindowIsOnscreen as String])
        XCTAssertNotNil(WindowEnumerator.offSpaceWindowInfo(from: entry(onscreen: nil), pid: 42))
    }

    func testOtherProcessIsExcluded() {
        XCTAssertNil(WindowEnumerator.offSpaceWindowInfo(from: entry(pid: 7), pid: 42))
    }

    func testNonWindowLayerIsExcluded() {
        // Menus, panels, the Dock, etc. sit above the normal window layer.
        XCTAssertNil(WindowEnumerator.offSpaceWindowInfo(from: entry(layer: 25), pid: 42))
    }

    func testTinyOrTransparentSurfacesAreExcluded() {
        XCTAssertNil(WindowEnumerator.offSpaceWindowInfo(from: entry(width: 40, height: 30), pid: 42))
        XCTAssertNil(WindowEnumerator.offSpaceWindowInfo(from: entry(alpha: 0), pid: 42))
    }

    func testMissingTitleStillProducesAWindow() {
        // Without Screen Recording the name is absent — the window must still list.
        let window = WindowEnumerator.offSpaceWindowInfo(from: entry(name: nil), pid: 42)
        XCTAssertNotNil(window)
        XCTAssertEqual(window?.title, "")
    }
}
