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
        for error in [SVGRasterizer.RasterizeError.notSVG, .timedOut, .snapshotFailed] {
            XCTAssertFalse(error.message.isEmpty)
        }
    }

    // MARK: Content Security Policy

    /// The whole no-network guarantee for untrusted markup. `decidePolicyFor` only
    /// sees page navigations, so without this an `<image href="https://tracker/…">`
    /// in a hostile SVG fires silently and leaks the user's IP.
    func testDocumentForbidsEverySubresourceByDefault() {
        let html = SVGRasterizer.htmlDocument(forSVG: "<svg></svg>")
        XCTAssertTrue(html.contains("Content-Security-Policy"))
        XCTAssertTrue(html.contains("default-src 'none'"))
    }

    /// A `<meta>` policy applies from where the parser reads it, so anything ahead
    /// of it in the document would load unprotected. It has to be first.
    func testPolicyPrecedesTheMarkupItGoverns() {
        let html = SVGRasterizer.htmlDocument(forSVG: "<svg id=\"marker\"></svg>")
        guard let policy = html.range(of: "Content-Security-Policy"),
              let markup = html.range(of: "id=\"marker\"") else {
            XCTFail("expected both the policy and the markup in the document")
            return
        }
        XCTAssertTrue(policy.lowerBound < markup.lowerBound)
        // And ahead of the stylesheet and charset too — nothing precedes it.
        XCTAssertTrue(html.contains("<head><meta http-equiv=\"Content-Security-Policy\""))
    }

    /// Two exceptions, both deliberate: the wrapper's own `<style>` is inline, and
    /// a `data:` image is bytes already in hand rather than a request. Neither is a
    /// path off the machine — but a policy that quietly allowed `https:` would be.
    func testPolicyAllowsOnlyInlineStyleAndDataImages() {
        let policy = SVGRasterizer.contentSecurityPolicy
        XCTAssertTrue(policy.contains("style-src 'unsafe-inline'"))
        XCTAssertTrue(policy.contains("img-src data:"))
        XCTAssertFalse(policy.contains("http"))
        XCTAssertFalse(policy.contains("*"))
    }
}
