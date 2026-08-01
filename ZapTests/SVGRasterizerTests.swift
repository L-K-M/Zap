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
        let html = SVGRasterizer.htmlDocument(forSVG: "<svg id=\"marker\"></svg>")
        XCTAssertTrue(html.contains("<svg id=\"marker\"></svg>"))
    }

    func testDocumentIsTransparentAndFillsTheViewport() {
        let html = SVGRasterizer.htmlDocument(forSVG: "<svg></svg>")
        // Transparent, or the snapshot comes back on white and the alpha
        // classifier reads every icon as full-bleed.
        XCTAssertTrue(html.contains("background:transparent"))
        XCTAssertTrue(html.contains("width:100vw"))
        XCTAssertTrue(html.contains("height:100vh"))
    }

    func testErrorsCarryAMessage() {
        for error in [SVGRasterizer.RasterizeError.notSVG, .timedOut, .snapshotFailed, .unprotected] {
            XCTAssertFalse(error.message.isEmpty)
        }
    }

    /// Refusing to render because the block list wouldn't compile is not the same
    /// as artwork that won't draw: it happens to *every* SVG on that machine, so
    /// it must not read as a complaint about the file the user just picked.
    func testRefusingToRenderUnprotectedReadsDifferentlyFromABadFile() {
        let unprotected = SVGRasterizer.RasterizeError.unprotected
        XCTAssertNotEqual(unprotected, .snapshotFailed)
        XCTAssertNotEqual(unprotected.message, SVGRasterizer.RasterizeError.snapshotFailed.message)
        XCTAssertNotEqual(unprotected.message, SVGRasterizer.RasterizeError.notSVG.message)
    }
}
