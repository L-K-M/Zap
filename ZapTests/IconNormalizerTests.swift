import CoreGraphics
import Foundation
import XCTest
@testable import Zap

final class IconNormalizerTests: XCTestCase {

    /// Ink the artwork carries once the layout's scale is applied, in the same
    /// units as `targetExtent` squared. This is the quantity normalisation is
    /// supposed to hold constant across shapes.
    private func resultingInk(_ layout: IconNormalizer.Layout,
                              inkFraction: Double, width: Double, height: Double) -> Double {
        inkFraction * (layout.scale * width) * (layout.scale * height)
    }

    // MARK: Equal ink

    /// The rule the whole normaliser exists for: a circle and a square end up
    /// carrying the same amount of ink, so they read as the same size in the row.
    func testCircleAndSquareLandAtEqualInk() {
        let extent = 100.0
        let square = IconNormalizer.layout(inkFraction: 1.0, trimmedWidth: extent,
                                           trimmedHeight: extent, targetExtent: extent, bleed: 0.15)
        let circle = IconNormalizer.layout(inkFraction: 0.785, trimmedWidth: extent,
                                           trimmedHeight: extent, targetExtent: extent, bleed: 0.15)

        let squareInk = resultingInk(square, inkFraction: 1.0, width: extent, height: extent)
        let circleInk = resultingInk(circle, inkFraction: 0.785, width: extent, height: extent)
        XCTAssertEqual(squareInk, circleInk, accuracy: extent * extent * 0.01)

        // ...and both hit the reference.
        XCTAssertEqual(squareInk, IconNormalizer.referenceInkFraction * extent * extent,
                       accuracy: extent * extent * 0.01)
    }

    /// A circle has to be wider than a square to carry the same ink — which is the
    /// reason bleed exists at all.
    func testCircleGrowsAndSolidSquareShrinksSlightly() {
        let extent = 100.0
        let square = IconNormalizer.layout(inkFraction: 1.0, trimmedWidth: extent,
                                           trimmedHeight: extent, targetExtent: extent, bleed: 0.15)
        let circle = IconNormalizer.layout(inkFraction: 0.785, trimmedWidth: extent,
                                           trimmedHeight: extent, targetExtent: extent, bleed: 0.15)

        XCTAssertLessThan(square.scale, 1)
        XCTAssertGreaterThan(circle.scale, 1)
        XCTAssertEqual(circle.scale, 1.1, accuracy: 0.02)
    }

    func testWideArtworkIsScaledByAreaNotByWidth() {
        // A 2:1 solid bar. Fitting it to the frame by *width* would halve its
        // visual weight; matching ink keeps it comparable.
        let extent = 100.0
        let bar = IconNormalizer.layout(inkFraction: 1.0, trimmedWidth: 200,
                                        trimmedHeight: 100, targetExtent: extent, bleed: 0.15)
        let ink = resultingInk(bar, inkFraction: 1.0, width: 200, height: 100)
        // Clamped by the canvas (a 2:1 bar can't reach equal ink inside a square
        // frame), but it must still be scaled up from a naive width fit.
        XCTAssertTrue(bar.wasClamped)
        XCTAssertGreaterThan(ink, 0.4 * extent * extent)
    }

    // MARK: Clamping

    func testSparseArtworkIsClampedByTheBleed() {
        // A thin cross covers about half its bounding box; chasing equal ink would
        // grow it by 1.37×, past the 1.16× the bleed allows.
        let layout = IconNormalizer.layout(inkFraction: 0.51, trimmedWidth: 100,
                                           trimmedHeight: 100, targetExtent: 100, bleed: 0.08)
        XCTAssertTrue(layout.wasClamped)
        XCTAssertEqual(layout.scale, 1.16, accuracy: 0.001)
    }

    func testWithoutBleedNothingMayGrowPastTheFrame() {
        let circle = IconNormalizer.layout(inkFraction: 0.785, trimmedWidth: 100,
                                           trimmedHeight: 100, targetExtent: 100, bleed: 0)
        XCTAssertTrue(circle.wasClamped)
        XCTAssertEqual(circle.scale, 1, accuracy: 0.001)
    }

    func testSolidSquareNeedsNoBleed() {
        let square = IconNormalizer.layout(inkFraction: 1.0, trimmedWidth: 100,
                                           trimmedHeight: 100, targetExtent: 100, bleed: 0)
        XCTAssertFalse(square.wasClamped)
    }

    func testBleedIsClampedToTheSupportedRange() {
        XCTAssertEqual(IconNormalizer.clampedBleed(-3), 0)
        XCTAssertEqual(IconNormalizer.clampedBleed(9), Double(IconRowMetrics.maximumBleed))
        XCTAssertEqual(IconNormalizer.clampedBleed(.nan), 0)
    }

    func testCanvasExtentMatchesTheRowMetrics() {
        // The normaliser's canvas and the view's image frame must agree, or the
        // cached bitmap won't fill the frame it's drawn into.
        for bleed in [0.0, 0.05, 0.08, 0.15] {
            XCTAssertEqual(IconNormalizer.canvasExtent(targetExtent: 80, bleed: bleed),
                           Double(IconRowMetrics.imageExtent(iconSize: 80, bleed: CGFloat(bleed))),
                           accuracy: 0.0001)
        }
    }

    // MARK: Degenerate input

    func testDegenerateInputIsLeftAlone() {
        for layout in [
            IconNormalizer.layout(inkFraction: 0, trimmedWidth: 100, trimmedHeight: 100,
                                  targetExtent: 100, bleed: 0.08),
            IconNormalizer.layout(inkFraction: 1, trimmedWidth: 0, trimmedHeight: 100,
                                  targetExtent: 100, bleed: 0.08),
            IconNormalizer.layout(inkFraction: 1, trimmedWidth: 100, trimmedHeight: 100,
                                  targetExtent: 0, bleed: 0.08),
            IconNormalizer.layout(inkFraction: .nan, trimmedWidth: 100, trimmedHeight: 100,
                                  targetExtent: 100, bleed: 0.08),
        ] {
            XCTAssertEqual(layout.scale, 1)
            XCTAssertFalse(layout.wasClamped)
        }
    }

    // MARK: Rendering

    func testNormalizeRendersIntoTheBleedCanvas() {
        let image = IconTestSupport.makeImage(width: 512, height: 512, filled: false)
        let result = IconNormalizer.normalize(image, targetExtent: 200, bleed: 0.1,
                                              trim: true, shadow: false)
        // 200 * (1 + 0.2) = 240 on each side.
        XCTAssertEqual(result.width, 240)
        XCTAssertEqual(result.height, 240)
    }

    func testNormalizeWithoutBleedRendersAtTheNominalExtent() {
        let image = IconTestSupport.makeImage(width: 256, height: 256)
        let result = IconNormalizer.normalize(image, targetExtent: 128, bleed: 0,
                                              trim: true, shadow: false)
        XCTAssertEqual(result.width, 128)
    }

    /// Trimming has to find the artwork inside its transparent margin, or a padded
    /// icon stays small in its cell forever.
    func testTrimmingRecoversArtworkFromATransparentMargin() throws {
        // A circle occupying the middle half of an otherwise empty canvas.
        let side = 400
        let context = try XCTUnwrap(CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 1, green: 0.5, blue: 0, alpha: 1)
        context.fillEllipse(in: CGRect(x: 100, y: 100, width: 200, height: 200))
        let padded = try XCTUnwrap(context.makeImage())

        let trimmed = IconNormalizer.normalize(padded, targetExtent: 200, bleed: 0.15,
                                               trim: true, shadow: false)
        let untrimmed = IconNormalizer.normalize(padded, targetExtent: 200, bleed: 0.15,
                                                 trim: false, shadow: false)

        // Same canvas either way; what differs is how much of it the ink fills.
        XCTAssertEqual(trimmed.width, untrimmed.width)
        let trimmedInk = try inkFraction(of: trimmed)
        let untrimmedInk = try inkFraction(of: untrimmed)
        XCTAssertGreaterThan(trimmedInk, untrimmedInk * 1.5,
                             "trimming should put substantially more ink on the canvas")
    }

    func testShadowAddsCoverageOutsideTheArtwork() throws {
        let image = IconTestSupport.makeImage(width: 256, height: 256, filled: false)
        let plain = IconNormalizer.normalize(image, targetExtent: 200, bleed: 0.15,
                                             trim: true, shadow: false)
        let shadowed = IconNormalizer.normalize(image, targetExtent: 200, bleed: 0.15,
                                                trim: true, shadow: true)
        // The silhouette is drawn *outside* the art's own alpha, so partial
        // coverage rises even though the artwork is identical.
        XCTAssertGreaterThan(try inkFraction(of: shadowed, threshold: 8),
                             try inkFraction(of: plain, threshold: 8))
    }

    /// The shadow falls **below** the artwork, and that is the whole difference
    /// between a shadow and an outline.
    ///
    /// A centred one has no side the light comes from, so it edges every boundary
    /// equally — which on spiky artwork reads as a dark border traced around each
    /// point rather than as lift. This asserts the asymmetry directly: the faint
    /// coverage reaches further past the bottom of the ink than past the top.
    ///
    /// A solid square, deliberately: it can't reach equal ink, so it is scaled
    /// *down* inside the bleed canvas and there is room for the shadow to land in
    /// rather than be clipped by the canvas edge.
    func testTheShadowFallsBelowTheArtwork() throws {
        let image = IconTestSupport.makeImage(width: 256, height: 256)
        let shadowed = IconNormalizer.normalize(image, targetExtent: 200, bleed: 0.15,
                                                trim: true, shadow: true)

        let mask = try XCTUnwrap(AlphaMask(image: shadowed, longestEdge: 128))
        // Row 0 is the top (`AlphaMask` samples through a bitmap context whose row 0
        // is the image's first row), so `maxRow` is the bottom edge.
        let ink = try XCTUnwrap(mask.inkBounds(threshold: 200), "the artwork itself")
        let withShadow = try XCTUnwrap(mask.inkBounds(threshold: 8), "artwork plus shadow")

        let reachBelow = withShadow.maxRow - ink.maxRow
        let reachAbove = ink.minRow - withShadow.minRow
        XCTAssertGreaterThan(reachBelow, 0, "the shadow has to show past the ink at all")
        XCTAssertGreaterThan(reachBelow, reachAbove,
                             "a shadow offset downward must reach further below than above")
    }

    /// Faint enough to be lift rather than a second shape. The old value was dark
    /// enough that on thin artwork the shadow read as ink in its own right.
    func testTheShadowNeverReadsAsInk() throws {
        let image = IconTestSupport.makeImage(width: 256, height: 256)
        let plain = IconNormalizer.normalize(image, targetExtent: 200, bleed: 0.15,
                                             trim: true, shadow: false)
        let shadowed = IconNormalizer.normalize(image, targetExtent: 200, bleed: 0.15,
                                                trim: true, shadow: true)

        // At the threshold the rest of the app calls ink, the shadow is invisible:
        // what it adds is confined to the partial coverage the test above measures.
        // A little slack for the artwork's own antialiased edge, which sits over the
        // shadow and so lands a shade more opaque than it would alone.
        XCTAssertLessThan(try inkFraction(of: shadowed),
                          try inkFraction(of: plain) * 1.1)
    }

    private func inkFraction(of image: CGImage, threshold: UInt8 = 128) throws -> Double {
        let mask = try XCTUnwrap(AlphaMask(image: image, longestEdge: 128))
        return Double(mask.inkCount(threshold: threshold)) / Double(mask.width * mask.height)
    }
}
