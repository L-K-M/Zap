import XCTest
import SwiftUI
@testable import Zap

/// The rules that translate the system's accessibility display settings into the
/// overlay's appearance.
final class AccessibilityDisplaySettingsTests: XCTestCase {

    func testConfiguredOpacityIsUsedNormally() {
        XCTAssertEqual(
            AccessibilityDisplaySettings.effectiveBackgroundOpacity(
                configured: 0.55, reduceTransparency: false),
            0.55)
    }

    func testReduceTransparencyMakesTheBackgroundOpaque() {
        XCTAssertEqual(
            AccessibilityDisplaySettings.effectiveBackgroundOpacity(
                configured: 0.2, reduceTransparency: true),
            1)
    }

    func testAlreadyOpaqueBackgroundIsUnchanged() {
        XCTAssertEqual(
            AccessibilityDisplaySettings.effectiveBackgroundOpacity(
                configured: 1, reduceTransparency: true),
            1)
    }

    func testAnimationsPassThroughNormally() {
        XCTAssertNotNil(
            AccessibilityDisplaySettings.effectiveAnimation(.easeOut(duration: 0.2),
                                                            reduceMotion: false))
    }

    func testReduceMotionDropsTheAnimation() {
        XCTAssertNil(
            AccessibilityDisplaySettings.effectiveAnimation(.easeOut(duration: 0.2),
                                                            reduceMotion: true))
    }

    func testLiveSettingsMirrorTheWorkspace() {
        // The published values must start from the system state, not a default.
        let settings = AccessibilityDisplaySettings()
        XCTAssertEqual(settings.reduceTransparency,
                       NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
        XCTAssertEqual(settings.reduceMotion,
                       NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
}
