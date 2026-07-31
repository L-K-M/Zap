import CoreGraphics
import Foundation
import XCTest
@testable import Zap

final class IconImageValidatorTests: XCTestCase {

    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = IconTestSupport.makeTemporaryDirectory()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        super.tearDown()
    }

    // MARK: The §6.2 accept/reject table

    func testComfortableSizeIsAccepted() throws {
        let measurements = try XCTUnwrap(IconImageValidator.check(pixelWidth: 512, pixelHeight: 512).successValue)
        XCTAssertEqual(measurements.pixelWidth, 512)
        XCTAssertFalse(measurements.isLowResolution)
    }

    func testAtTheWarningThresholdIsNotYetLowResolution() throws {
        let measurements = try XCTUnwrap(IconImageValidator.check(pixelWidth: 128, pixelHeight: 128).successValue)
        XCTAssertFalse(measurements.isLowResolution)
    }

    func testBelowTheWarningThresholdIsAcceptedButFlagged() throws {
        let measurements = try XCTUnwrap(IconImageValidator.check(pixelWidth: 100, pixelHeight: 100).successValue)
        XCTAssertTrue(measurements.isLowResolution)
    }

    func testAtTheHardFloorIsAccepted() {
        XCTAssertNotNil(IconImageValidator.check(pixelWidth: 64, pixelHeight: 64).successValue)
    }

    func testBelowTheHardFloorIsRejected() {
        XCTAssertEqual(IconImageValidator.check(pixelWidth: 63, pixelHeight: 63).failureValue,
                       .tooSmall(width: 63, height: 63))
    }

    func testOversizeAxisIsRejected() {
        XCTAssertEqual(IconImageValidator.check(pixelWidth: 9000, pixelHeight: 9000).failureValue,
                       .tooLarge(width: 9000, height: 9000))
    }

    /// 8000 × 8000 clears the per-axis cap and is still 64 MP — the case the total
    /// check exists for.
    func testDecompressionBombWithinTheAxisCapIsRejected() {
        XCTAssertEqual(IconImageValidator.check(pixelWidth: 8000, pixelHeight: 8000).failureValue,
                       .tooManyPixels(count: 64_000_000))
    }

    func testAspectRatioBoundsAreInclusive() {
        XCTAssertNotNil(IconImageValidator.check(pixelWidth: 512, pixelHeight: 256).successValue)
        XCTAssertNotNil(IconImageValidator.check(pixelWidth: 256, pixelHeight: 512).successValue)
    }

    func testExtremeAspectRatiosAreRejected() {
        guard case .extremeAspectRatio = IconImageValidator.check(pixelWidth: 2000, pixelHeight: 200).failureValue else {
            return XCTFail("a 10:1 banner should be rejected")
        }
        guard case .extremeAspectRatio = IconImageValidator.check(pixelWidth: 200, pixelHeight: 2000).failureValue else {
            return XCTFail("a 1:10 banner should be rejected")
        }
    }

    func testOversizeFileIsRejectedBeforeAnythingElse() {
        let bytes = IconImageValidator.Limits.maximumSourceBytes + 1
        XCTAssertEqual(IconImageValidator.check(pixelWidth: 512, pixelHeight: 512, byteCount: bytes).failureValue,
                       .fileTooLarge(bytes: bytes))
    }

    func testZeroDimensionsAreUnreadable() {
        XCTAssertEqual(IconImageValidator.check(pixelWidth: 0, pixelHeight: 0).failureValue, .unreadable)
    }

    func testAlphaIsReportedThrough() throws {
        let withAlpha = try XCTUnwrap(
            IconImageValidator.check(pixelWidth: 512, pixelHeight: 512, hasAlpha: true).successValue)
        XCTAssertTrue(withAlpha.hasAlpha)
        let without = try XCTUnwrap(
            IconImageValidator.check(pixelWidth: 512, pixelHeight: 512, hasAlpha: false).successValue)
        XCTAssertFalse(without.hasAlpha)
    }

    // MARK: Decoding

    func testDecodesAPNGFromDisk() throws {
        let url = IconTestSupport.writePNG(width: 256, height: 256,
                                           to: directory.appendingPathComponent("icon.png"))
        let image = try XCTUnwrap(IconImageValidator.decode(contentsOf: url).successValue)
        XCTAssertEqual(image.width, 256)
        XCTAssertEqual(image.height, 256)
    }

    /// The decode is bounded by what we ask for, not by what the header claims.
    func testDecodeIsBoundedToTheMasterSize() throws {
        let url = IconTestSupport.writePNG(width: 2048, height: 2048,
                                           to: directory.appendingPathComponent("big.png"))
        let image = try XCTUnwrap(IconImageValidator.decode(contentsOf: url).successValue)
        XCTAssertEqual(image.width, IconImageValidator.Limits.masterLongestEdge)
    }

    func testDecodeDoesNotUpscaleASmallSource() throws {
        let url = IconTestSupport.writePNG(width: 128, height: 128,
                                           to: directory.appendingPathComponent("small.png"))
        let image = try XCTUnwrap(IconImageValidator.decode(contentsOf: url).successValue)
        XCTAssertEqual(image.width, 128)
    }

    func testDecodeRejectsAnUndersizeImage() throws {
        let url = IconTestSupport.writePNG(width: 32, height: 32,
                                           to: directory.appendingPathComponent("tiny.png"))
        XCTAssertEqual(IconImageValidator.decode(contentsOf: url).failureValue, .tooSmall(width: 32, height: 32))
    }

    func testDecodeRejectsNonImageData() {
        XCTAssertEqual(IconImageValidator.decode(data: Data("this is not an image".utf8)).failureValue, .unreadable)
    }

    func testDecodeRejectsAMissingFile() {
        let missing = directory.appendingPathComponent("nope.png")
        XCTAssertEqual(IconImageValidator.decode(contentsOf: missing).failureValue, .unreadable)
    }

    func testMeasureReadsTheHeaderWithoutDecoding() throws {
        let url = IconTestSupport.writePNG(width: 512, height: 512,
                                           to: directory.appendingPathComponent("measured.png"))
        let measurements = try XCTUnwrap(IconImageValidator.measure(contentsOf: url).successValue)
        XCTAssertEqual(measurements.pixelWidth, 512)
        XCTAssertEqual(measurements.pixelHeight, 512)
    }

    // MARK: Encoding

    func testWritePNGRoundTrips() throws {
        let url = directory.appendingPathComponent("out.png")
        let image = IconTestSupport.makeImage(width: 300, height: 300)
        guard case .success = IconImageValidator.writePNG(image, to: url) else {
            return XCTFail("writing the PNG failed")
        }
        let reloaded = try XCTUnwrap(IconImageValidator.decode(contentsOf: url).successValue)
        XCTAssertEqual(reloaded.width, 300)
    }
}

// MARK: - Result conveniences

extension Result {
    /// The success value, or `nil` — so a test can `XCTUnwrap` it. Named to stay
    /// clear of the `success`/`failure` cases themselves.
    var successValue: Success? {
        guard case .success(let value) = self else { return nil }
        return value
    }

    /// The failure value, or `nil`.
    var failureValue: Failure? {
        guard case .failure(let error) = self else { return nil }
        return error
    }
}
