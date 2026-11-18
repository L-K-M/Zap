import CoreGraphics
import XCTest
@testable import Zap

/// How large a window preview is captured, in pixels, for the display it will
/// be drawn on (`WindowPreviewMetrics.capturePixelDimension`).
final class WindowPreviewCaptureSizeTests: XCTestCase {

    /// The regression: previews were captured at the point size (160 px) on
    /// every display, so on a 2× display each 120-pt tile (240 px) was upscaled.
    func testCaptureCoversTheTilesPixelsAtEveryCommonScale() {
        for scale: CGFloat in [1, 1.5, 2, 3] {
            let pixels = WindowPreviewMetrics.capturePixelDimension(backingScale: scale)
            XCTAssertGreaterThanOrEqual(pixels, WindowPreviewMetrics.rowWidth * scale,
                                        "a \(scale)× tile would be upscaled")
            XCTAssertGreaterThanOrEqual(pixels, WindowGridMetrics.thumbWidth * scale)
        }
    }

    func testScalesThePointBudgetByTheBackingScale() {
        XCTAssertEqual(WindowPreviewMetrics.capturePixelDimension(backingScale: 1), 160)
        XCTAssertEqual(WindowPreviewMetrics.capturePixelDimension(backingScale: 2), 320)
        XCTAssertEqual(WindowPreviewMetrics.capturePixelDimension(backingScale: 3), 480)
    }

    func testFractionalScaleRoundsUpToWholePixels() {
        XCTAssertEqual(WindowPreviewMetrics.capturePixelDimension(backingScale: 1.75), 280)
        XCTAssertEqual(WindowPreviewMetrics.capturePixelDimension(backingScale: 1.333), 214)
    }

    func testScaleIsCappedSoNoDisplayCostsUnboundedMemory() {
        XCTAssertEqual(WindowPreviewMetrics.capturePixelDimension(backingScale: 8),
                       WindowPreviewMetrics.capturePixelDimension(backingScale: WindowPreviewMetrics.maximumBackingScale))
    }

    func testNonsensicalScalesCountAsOneX() {
        for scale: CGFloat in [0, -2, 0.5, .nan, .infinity, -.infinity] {
            XCTAssertEqual(WindowPreviewMetrics.capturePixelDimension(backingScale: scale),
                           WindowPreviewMetrics.maxDimension, "scale \(scale)")
        }
    }
}
