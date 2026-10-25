import CoreGraphics
import XCTest
@testable import Zap

/// Tests `WindowThumbnailProvider.downsample`, the pure scaling step the macOS 13
/// capture path needs because `CGWindowListCreateImage` cannot bound its output.
/// Synthetic context-backed images only — no screen capture, no permissions.
final class WindowThumbnailScalingTests: XCTestCase {

    private func makeImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil,
                                width: width,
                                height: height,
                                bitsPerComponent: 8,
                                bytesPerRow: 0,
                                space: colorSpace,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0.5, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func scaled(_ image: CGImage,
                        maxDimension: CGFloat = 160) -> CGImage? {
        WindowThumbnailProvider.downsample(image, maxDimension: maxDimension)
    }

    func testLandscapeIsScaledToMaxDimension() {
        let result = scaled(makeImage(width: 1024, height: 512))
        XCTAssertEqual(result?.width, 160)
        XCTAssertEqual(result?.height, 80)
    }

    func testPortraitIsScaledToMaxDimension() {
        let result = scaled(makeImage(width: 512, height: 1024))
        XCTAssertEqual(result?.width, 80)
        XCTAssertEqual(result?.height, 160)
    }

    func testOddDimensionsStayBoundedAndAspectPreserving() {
        let source = makeImage(width: 1023, height: 513)
        let result = scaled(source)
        XCTAssertNotNil(result)
        XCTAssertLessThanOrEqual(max(result!.width, result!.height), 160)
        let sourceAspect = 1023.0 / 513.0
        let resultAspect = Double(result!.width) / Double(result!.height)
        XCTAssertEqual(resultAspect, sourceAspect, accuracy: 0.02)
    }

    func testImageThatFitsIsReturnedUnchanged() {
        let source = makeImage(width: 80, height: 40)
        let result = scaled(source)
        XCTAssertTrue(result === source)
        XCTAssertEqual(result?.width, 80)
        XCTAssertEqual(result?.height, 40)
    }

    /// A fractional limit is floored to whole pixels so the rounded output can
    /// never exceed the promised bound (159.75 -> 159, not a 160 rounding-up).
    func testFractionalMaxDimensionFloorsToIntegralLimit() {
        let result = scaled(makeImage(width: 1024, height: 512), maxDimension: 159.75)
        XCTAssertEqual(result?.width, 159)
        XCTAssertEqual(result?.height, 80)
    }

    func testFractionalLimitBelowTwoFloorsToOnePixel() {
        let result = scaled(makeImage(width: 4, height: 4), maxDimension: 1.5)
        XCTAssertEqual(result?.width, 1)
        XCTAssertEqual(result?.height, 1)
    }

    func testNonPositiveMaxDimensionIsRejected() {
        let source = makeImage(width: 1024, height: 512)
        XCTAssertNil(scaled(source, maxDimension: 0))
        XCTAssertNil(scaled(source, maxDimension: -10))
    }

    func testNonFiniteMaxDimensionIsRejected() {
        let source = makeImage(width: 1024, height: 512)
        XCTAssertNil(scaled(source, maxDimension: .nan))
        XCTAssertNil(scaled(source, maxDimension: .infinity))
        XCTAssertNil(scaled(source, maxDimension: -.infinity))
    }
}
