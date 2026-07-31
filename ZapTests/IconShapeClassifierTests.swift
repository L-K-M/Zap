import CoreGraphics
import Foundation
import XCTest
@testable import Zap

final class IconShapeClassifierTests: XCTestCase {

    // MARK: Synthetic shapes

    /// Rasterises a unit-square predicate onto an alpha mask, the same way the
    /// classifier samples a real image.
    private func mask(size: Int = IconShapeClassifier.sampleResolution,
                      _ shape: (Double, Double) -> Bool) -> AlphaMask {
        var samples = [UInt8](repeating: 0, count: size * size)
        for row in 0..<size {
            let y = (Double(row) + 0.5) / Double(size)
            for column in 0..<size {
                let x = (Double(column) + 0.5) / Double(size)
                samples[row * size + column] = shape(x, y) ? 255 : 0
            }
        }
        return AlphaMask(width: size, height: size, samples: samples)!
    }

    private func roundedRect(radius: Double) -> (Double, Double) -> Bool {
        { x, y in
            let dx = max(radius - x, x - (1 - radius), 0)
            let dy = max(radius - y, y - (1 - radius), 0)
            return dx * dx + dy * dy <= radius * radius
        }
    }

    private func superellipse(exponent: Double) -> (Double, Double) -> Bool {
        { x, y in
            pow(abs(2 * x - 1), exponent) + pow(abs(2 * y - 1), exponent) <= 1
        }
    }

    private let circle: (Double, Double) -> Bool = { x, y in
        (x - 0.5) * (x - 0.5) + (y - 0.5) * (y - 0.5) <= 0.25
    }

    private let square: (Double, Double) -> Bool = { _, _ in true }

    /// A cross — a stand-in for the free-form artwork the feature exists for.
    private let cross: (Double, Double) -> Bool = { x, y in
        (x >= 0.35 && x <= 0.65) || (y >= 0.35 && y <= 0.65)
    }

    /// Scales a shape into the middle `fraction` of the canvas, leaving the
    /// transparent margin a Big Sur "plate" icon carries.
    private func inset(_ fraction: Double,
                       _ shape: @escaping (Double, Double) -> Bool) -> (Double, Double) -> Bool {
        let margin = (1 - fraction) / 2
        return { x, y in
            guard x >= margin, x <= 1 - margin, y >= margin, y <= 1 - margin else { return false }
            return shape((x - margin) / fraction, (y - margin) / fraction)
        }
    }

    private func classify(_ shape: (Double, Double) -> Bool) -> IconShape {
        IconShapeClassifier.classify(IconShapeClassifier.profile(of: mask(shape)))
    }

    private func profile(_ shape: (Double, Double) -> Bool) -> AlphaProfile {
        IconShapeClassifier.profile(of: mask(shape))
    }

    // MARK: Classification

    func testOpaqueSquareIsFullBleed() {
        XCTAssertEqual(classify(square), .fullBleed)
    }

    func testRoundedPlateIsARoundedSquare() {
        XCTAssertEqual(classify(inset(0.8, roundedRect(radius: 0.225))), .roundedSquare)
    }

    func testSuperellipseIsARoundedSquare() {
        XCTAssertEqual(classify(superellipse(exponent: 5)), .roundedSquare)
    }

    func testCircleIsFreeform() {
        XCTAssertEqual(classify(circle), .freeform)
    }

    func testCrossIsFreeform() {
        XCTAssertEqual(classify(cross), .freeform)
    }

    func testTransparentArtworkIsEmpty() {
        XCTAssertEqual(classify { _, _ in false }, .empty)
    }

    func testFullBleedRoundedArtworkIsNotTreatedAsHardCornered() {
        // Fills the canvas but has rounded corners: substituting it needs no extra
        // corner mask, so it must not be classified as full-bleed.
        XCTAssertEqual(classify(roundedRect(radius: 0.225)), .roundedSquare)
    }

    // MARK: Actions

    func testOnlyFullBleedArtworkGetsACornerMask() {
        XCTAssertTrue(IconShape.fullBleed.needsCornerMask)
        XCTAssertFalse(IconShape.roundedSquare.needsCornerMask)
        XCTAssertFalse(IconShape.freeform.needsCornerMask)
    }

    func testOnlyEmptyArtworkIsNotWorthSubstituting() {
        XCTAssertFalse(IconShape.empty.isWorthSubstituting)
        for shape in IconShape.allCases where shape != .empty {
            XCTAssertTrue(shape.isWorthSubstituting)
        }
    }

    // MARK: Measurements

    func testProfileMeasuresBoundsFillAndCorners() {
        let plate = profile(inset(0.8, roundedRect(radius: 0.225)))
        XCTAssertEqual(plate.boundsWidth, 0.8, accuracy: 0.02)
        XCTAssertEqual(plate.boundsHeight, 0.8, accuracy: 0.02)
        XCTAssertEqual(plate.fillRatio, 0.947, accuracy: 0.02)
        // 0.141, not the 0.132 a continuous rounded rect of this radius would
        // give, and not the 0.113 the *full-canvas* plate measures below: an inset
        // shape's bounding box is 52 cells, so one grid cell is 0.027 of the
        // half-diagonal and the measurement lands a third of a cell out. Well
        // clear of the 0.20 rounded-square boundary either way.
        XCTAssertEqual(plate.cornerReach, 0.141, accuracy: 0.005)

        let solid = profile(square)
        XCTAssertEqual(solid.fillRatio, 1, accuracy: 0.001)
        XCTAssertEqual(solid.cornerReach, 0, accuracy: 0.001)

        let round = profile(circle)
        XCTAssertEqual(round.fillRatio, 0.788, accuracy: 0.02)
        XCTAssertEqual(round.cornerReach, 0.273, accuracy: 0.02)
    }

    /// The measurement behind merging §4.2's `plate` and `alreadySquircle` into one
    /// class: a Big Sur plate and a Tahoe superellipse are the same shape as far as
    /// an alpha channel is concerned, so any threshold splitting them would be a
    /// coin flip. If this ever stops being true, the merge can be revisited.
    func testPlateAndSuperellipseAreNotSeparableByAlphaGeometry() {
        let plate = profile(roundedRect(radius: 0.225))
        let squircle = profile(superellipse(exponent: 5))

        XCTAssertEqual(plate.fillRatio, squircle.fillRatio, accuracy: 0.01)
        XCTAssertEqual(plate.cornerReach, squircle.cornerReach, accuracy: 0.01)
        XCTAssertEqual(IconShapeClassifier.classify(plate), IconShapeClassifier.classify(squircle))

        // ...whereas the boundaries that *do* change what gets drawn are wide.
        let solid = profile(square)
        let round = profile(circle)
        XCTAssertGreaterThan(solid.fillRatio - plate.fillRatio, 0.03)
        XCTAssertGreaterThan(plate.fillRatio - round.fillRatio, 0.15)
        XCTAssertGreaterThan(round.cornerReach - plate.cornerReach, 0.1)
    }

    func testNonSquareArtworkKeepsItsProportions() {
        // A circle centred in a 2:1 canvas must not be stretched into filling it.
        let width = 64
        let height = 32
        var samples = [UInt8](repeating: 0, count: width * height)
        for row in 0..<height {
            let y = (Double(row) + 0.5) / Double(height)
            for column in 0..<width {
                let x = (Double(column) + 0.5) / Double(width)
                // A circle of diameter = the canvas height, centred.
                let dx = (x - 0.5) * 2
                let dy = (y - 0.5)
                samples[row * width + column] = (dx * dx + dy * dy <= 0.25) ? 255 : 0
            }
        }
        let profile = IconShapeClassifier.profile(of: AlphaMask(width: width, height: height, samples: samples)!)
        XCTAssertEqual(profile.boundsWidth, 0.5, accuracy: 0.05)
        XCTAssertEqual(profile.boundsHeight, 1, accuracy: 0.05)
        XCTAssertEqual(IconShapeClassifier.classify(profile), .freeform)
    }

    // MARK: Through Core Graphics

    /// The synthetic-mask tests above exercise the arithmetic; this one proves the
    /// rasterisation path in between actually works on a real `CGImage`.
    func testClassifiesARealCGImage() throws {
        let size = 256
        let context = try XCTUnwrap(CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fillEllipse(in: CGRect(x: 0, y: 0, width: size, height: size))
        let image = try XCTUnwrap(context.makeImage())

        XCTAssertEqual(IconShapeClassifier.classify(image), .freeform)

        let measured = try XCTUnwrap(IconShapeClassifier.profile(of: image))
        XCTAssertEqual(measured.fillRatio, 0.788, accuracy: 0.03)
    }

    func testFullyOpaqueCGImageIsFullBleed() throws {
        let size = 128
        let context = try XCTUnwrap(CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0, green: 0.4, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        let image = try XCTUnwrap(context.makeImage())

        XCTAssertEqual(IconShapeClassifier.classify(image), .fullBleed)
    }
}
