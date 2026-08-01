import CoreGraphics
import Foundation
import XCTest
@testable import Zap

/// The pure halves of SVG rasterisation. The render itself drives a `WKWebView`
/// and is on the manual list — the sniffing and the document it builds are not.
final class SVGRasterizerTests: XCTestCase {

    private func data(_ string: String) -> Data { Data(string.utf8) }

    // MARK: Sniffing

    func testAcceptsPlainSVG() {
        XCTAssertTrue(SVGRasterizer.isSVG(data("<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>")))
    }

    func testAcceptsSVGBehindADeclarationOrComment() {
        XCTAssertTrue(SVGRasterizer.isSVG(data("<?xml version=\"1.0\"?><svg></svg>")))
        XCTAssertTrue(SVGRasterizer.isSVG(data("<!-- drawn by someone --><svg></svg>")))
        XCTAssertTrue(SVGRasterizer.isSVG(data(
            "<!DOCTYPE svg PUBLIC \"-//W3C//DTD SVG 1.1//EN\" \"x.dtd\"><svg></svg>")))
    }

    func testSniffingIsCaseInsensitive() {
        XCTAssertTrue(SVGRasterizer.isSVG(data("<SVG></SVG>")))
    }

    func testRejectsNonSVG() {
        XCTAssertFalse(SVGRasterizer.isSVG(data("just some words")))
        XCTAssertFalse(SVGRasterizer.isSVG(data("<html><body>no</body></html>")))
        XCTAssertFalse(SVGRasterizer.isSVG(Data()))
        // PNG magic bytes: binary, and not valid UTF-8 past the header.
        XCTAssertFalse(SVGRasterizer.isSVG(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])))
    }

    /// The type comes from the bytes, never from an extension or a `Content-Type`
    /// (§6.1) — a file merely *named* `.svg` proves nothing.
    func testSniffingIgnoresWhatAFileIsCalled() {
        XCTAssertFalse(SVGRasterizer.isSVG(data("this file is called icon.svg")))
    }

    // MARK: Document

    func testDocumentEmbedsTheMarkup() {
        let html = SVGRasterizer.htmlDocument(forSVG: "<svg id=\"marker\"></svg>",
                                              background: SVGRasterizer.blackBackdrop)
        XCTAssertTrue(html.contains("<svg id=\"marker\"></svg>"))
    }

    /// The backdrop is opaque and it is the one asked for. Transparency is not
    /// requested from WebKit any more — it composites onto white whichever way the
    /// page is captured — so each pass paints its own background and the alpha
    /// comes from the difference between two of them.
    func testDocumentPaintsTheBackdropItWasGivenAndFillsTheViewport() {
        for backdrop in [SVGRasterizer.blackBackdrop, SVGRasterizer.whiteBackdrop] {
            let html = SVGRasterizer.htmlDocument(forSVG: "<svg></svg>", background: backdrop)
            XCTAssertTrue(html.contains("background:\(backdrop)"))
            XCTAssertFalse(html.contains("background:transparent"))
            XCTAssertTrue(html.contains("width:100vw"))
            XCTAssertTrue(html.contains("height:100vh"))
        }
    }

    /// They have to differ, and be the extremes: `white − black` is the whole
    /// signal, so any other pair narrows the range alpha can be recovered from.
    func testTheTwoBackdropsAreOpaqueOpposites() {
        XCTAssertNotEqual(SVGRasterizer.blackBackdrop, SVGRasterizer.whiteBackdrop)
        XCTAssertEqual(SVGRasterizer.blackBackdrop, "#000")
        XCTAssertEqual(SVGRasterizer.whiteBackdrop, "#fff")
    }

    // MARK: PDF → bitmap

    /// The half of the render that isn't WebKit's: a PDF page drawn into a context
    /// Zap made. Exercised with a PDF built here, so the transparency claim is
    /// tested even though driving the web view isn't (`UNJAILED.md §9`).
    private func onePagePDF(width: CGFloat, height: CGFloat,
                            draw: (CGContext) -> Void = { _ in }) -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: width, height: height)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
        context.beginPDFPage(nil)
        draw(context)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    /// The reason this replaced `takeSnapshot`: a snapshot came back composited on
    /// opaque white, so an SVG that is nothing but a `<path>` became a white tile.
    func testAPageThatDrawsNothingStaysTransparent() throws {
        let image = try XCTUnwrap(
            SVGRasterizer.image(fromPDF: onePagePDF(width: 100, height: 100), side: 64))
        XCTAssertEqual(image.width, 64)

        // Nothing was drawn, so nothing should have appeared — least of all a
        // background. `.empty` is the classifier's name for "no ink anywhere",
        // and it is the reading a white tile could never produce.
        let mask = try XCTUnwrap(AlphaMask(image: image, longestEdge: 64))
        XCTAssertEqual(mask.inkCount(threshold: 1), 0)
        XCTAssertEqual(IconShapeClassifier.classify(image), .empty)
    }

    /// What the page *does* draw survives the trip.
    func testMarksOnThePageAreDrawn() throws {
        let pdf = onePagePDF(width: 100, height: 100) { context in
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }
        let image = try XCTUnwrap(SVGRasterizer.image(fromPDF: pdf, side: 64))
        let mask = try XCTUnwrap(AlphaMask(image: image, longestEdge: 64))
        XCTAssertEqual(mask.inkCount(threshold: 1), 64 * 64)
    }

    /// Fitted, not stretched — a wide page letterboxes into transparency rather
    /// than distorting to fill a square.
    func testANonSquarePageIsFittedRatherThanStretched() throws {
        let pdf = onePagePDF(width: 200, height: 100) { context in
            context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        }
        let image = try XCTUnwrap(SVGRasterizer.image(fromPDF: pdf, side: 64))
        XCTAssertEqual(image.width, 64)
        XCTAssertEqual(image.height, 64)

        // A 2:1 page centred in a square leaves the top and bottom quarters empty
        // and fills the middle. Stretching would have inked all four corners.
        let mask = try XCTUnwrap(AlphaMask(image: image, longestEdge: 64))
        XCTAssertTrue(mask.isInk(row: 32, column: 32, threshold: 1))
        XCTAssertFalse(mask.isInk(row: 1, column: 32, threshold: 1))
        XCTAssertFalse(mask.isInk(row: 62, column: 32, threshold: 1))
    }

    /// Alpha at one pixel, addressed the way `CGImage` defines rows: index 0 is the
    /// top scanline. Deliberately not `AlphaMask`, which says outright that "row 0
    /// is whichever edge Core Graphics drew first" — it declines to define the very
    /// thing this test is about.
    private func alpha(of image: CGImage, x: Int, y: Int) -> UInt8 {
        pixel(of: image, x: x, y: y).a
    }

    /// One premultiplied RGBA pixel.
    private func pixel(of image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let width = image.width
        let height = image.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = rgba.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress,
                  let context = CGContext(data: base, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn, y >= 0, y < height, x >= 0, x < width else { return (0, 0, 0, 0) }
        let offset = (y * width + x) * 4
        return (rgba[offset], rgba[offset + 1], rgba[offset + 2], rgba[offset + 3])
    }

    // MARK: Alpha recovery

    /// An opaque solid, standing in for one pass of a render.
    private func solid(_ red: UInt8, _ green: UInt8, _ blue: UInt8, side: Int = 8) -> CGImage? {
        guard let context = IconRenderer.makeContext(width: side, height: side) else { return nil }
        context.setFillColor(red: CGFloat(red) / 255, green: CGFloat(green) / 255,
                             blue: CGFloat(blue) / 255, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        return context.makeImage()
    }

    /// Artwork that covered the backdrop completely reads the same on both, so
    /// nothing showed through and the alpha is full.
    func testOpaqueArtworkRecoversFullAlpha() throws {
        let composed = try XCTUnwrap(SVGRasterizer.alphaRecovered(
            black: XCTUnwrap(solid(200, 30, 40)), white: XCTUnwrap(solid(200, 30, 40))))
        let sample = pixel(of: composed, x: 4, y: 4)
        XCTAssertEqual(sample.a, 255)
        // Colour is carried through from the black pass, unchanged.
        XCTAssertEqual(sample.r, 200)
        XCTAssertEqual(sample.g, 30)
        XCTAssertEqual(sample.b, 40)
    }

    /// The case the whole exercise is for: bare backdrop on both passes, so the
    /// artwork drew nothing there. Rendered once, this is the white tile.
    func testBareBackdropRecoversZeroAlpha() throws {
        let composed = try XCTUnwrap(SVGRasterizer.alphaRecovered(
            black: XCTUnwrap(solid(0, 0, 0)), white: XCTUnwrap(solid(255, 255, 255))))
        XCTAssertEqual(alpha(of: composed, x: 4, y: 4), 0)
    }

    /// Half-covered: white artwork at α≈0.5 lands on 128 over black and 255 over
    /// white, and the difference says so.
    func testPartialCoverageRecoversPartialAlpha() throws {
        let composed = try XCTUnwrap(SVGRasterizer.alphaRecovered(
            black: XCTUnwrap(solid(128, 128, 128)), white: XCTUnwrap(solid(255, 255, 255))))
        let sample = pixel(of: composed, x: 4, y: 4)
        XCTAssertEqual(Int(sample.a), 128, accuracy: 2)
        // Premultiplied, so the stored colour is α·C — the black pass again.
        XCTAssertEqual(Int(sample.r), 128, accuracy: 2)
    }

    func testMismatchedPassesAreRefused() throws {
        XCTAssertNil(SVGRasterizer.alphaRecovered(black: try XCTUnwrap(solid(0, 0, 0, side: 8)),
                                                  white: try XCTUnwrap(solid(0, 0, 0, side: 16))))
    }

    /// Which way up the page comes out.
    ///
    /// Every other fixture here is vertically symmetric, so all of them pass under
    /// either orientation — this is the one that can tell them apart. PDF space puts
    /// y=0 at the *bottom*, so ink at high y is the top of the page and must land in
    /// the low-numbered rows of the bitmap.
    ///
    /// No flip is applied before `drawPDFPage`, and this asserts that's right: a
    /// bitmap context's user space is bottom-left too, and its first row in memory
    /// is the image's top. The two conventions already agree. `IconRenderer` relies
    /// on the same round trip for every downsampled icon in the switcher, which is
    /// why those aren't upside-down either.
    func testInkAtTheTopOfThePageLandsAtTheTopOfTheBitmap() throws {
        let pdf = onePagePDF(width: 100, height: 100) { context in
            context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 75, width: 100, height: 25))
        }
        let image = try XCTUnwrap(SVGRasterizer.image(fromPDF: pdf, side: 64))

        XCTAssertEqual(alpha(of: image, x: 32, y: 8), 255, "top quarter should be inked")
        XCTAssertEqual(alpha(of: image, x: 32, y: 56), 0, "bottom quarter should be clear")
    }

    func testGarbageIsNotAPDF() {
        XCTAssertNil(SVGRasterizer.image(fromPDF: Data("not a pdf".utf8), side: 64))
        XCTAssertNil(SVGRasterizer.image(fromPDF: Data(), side: 64))
    }

    func testErrorsCarryAMessage() {
        for error in [SVGRasterizer.RasterizeError.notSVG, .timedOut, .snapshotFailed] {
            XCTAssertFalse(error.message.isEmpty)
        }
    }

    // MARK: Content Security Policy

    /// The whole no-network guarantee for untrusted markup. `decidePolicyFor` only
    /// sees page navigations, so without this an `<image href="https://tracker/…">`
    /// in a hostile SVG fires silently and leaks the user's IP.
    func testDocumentForbidsEverySubresourceByDefault() {
        let html = SVGRasterizer.htmlDocument(forSVG: "<svg></svg>",
                                              background: SVGRasterizer.blackBackdrop)
        XCTAssertTrue(html.contains("Content-Security-Policy"))
        XCTAssertTrue(html.contains("default-src 'none'"))
    }

    /// A `<meta>` policy applies from where the parser reads it, so anything ahead
    /// of it in the document would load unprotected. It has to be first.
    func testPolicyPrecedesTheMarkupItGoverns() {
        let html = SVGRasterizer.htmlDocument(forSVG: "<svg id=\"marker\"></svg>",
                                              background: SVGRasterizer.blackBackdrop)
        guard let policy = html.range(of: "Content-Security-Policy"),
              let markup = html.range(of: "id=\"marker\"") else {
            XCTFail("expected both the policy and the markup in the document")
            return
        }
        XCTAssertTrue(policy.lowerBound < markup.lowerBound)
        // And ahead of the stylesheet and charset too — nothing precedes it.
        XCTAssertTrue(html.contains("<head><meta http-equiv=\"Content-Security-Policy\""))
    }

    /// Every source in the policy, under every directive, has to be one that cannot
    /// reach the network.
    ///
    /// Parsed rather than sniffed for bad substrings. Checking for `http` and `*`
    /// catches the regressions someone would think to look for and misses the rest
    /// — `ws:`, `ftp:`, or a bare `style-src 'unsafe-inline' evil.com` — which is
    /// exactly backwards for a rule whose job is to hold against the case nobody
    /// pictured. Allow-list the three sources that are bytes-in-hand, reject the
    /// concept of anything else.
    func testNoDirectiveAllowsASourceThatCanReachTheNetwork() {
        let offline: Set<String> = ["'none'", "'unsafe-inline'", "data:"]
        for directive in SVGRasterizer.contentSecurityPolicy.split(separator: ";") {
            let parts = directive.split(separator: " ").map(String.init)
            guard let name = parts.first else { continue }
            for source in parts.dropFirst() {
                XCTAssertTrue(offline.contains(source),
                              "\(name) allows '\(source)', which can reach the network")
            }
        }
    }

    /// The exceptions, named. Losing `font-src` doesn't fail anything above — it
    /// just makes an SVG that carries its own typeface render in the wrong one.
    func testPolicyNamesTheExceptionsItMeansTo() {
        let policy = SVGRasterizer.contentSecurityPolicy
        XCTAssertTrue(policy.hasPrefix("default-src 'none'"))
        XCTAssertTrue(policy.contains("style-src 'unsafe-inline'"))
        XCTAssertTrue(policy.contains("img-src data:"))
        XCTAssertTrue(policy.contains("font-src data:"))
    }

    /// The two directives that don't inherit from `default-src`, so a policy that
    /// leaves them out is silently narrower than it reads. Asserted separately
    /// because the parse test above can't catch a *missing* directive — every
    /// source it does name is `'none'`, which passes either way.
    func testPolicyStatesTheDirectivesThatDoNotInherit() {
        let policy = SVGRasterizer.contentSecurityPolicy
        XCTAssertTrue(policy.contains("base-uri 'none'"))
        XCTAssertTrue(policy.contains("form-action 'none'"))
    }
}
