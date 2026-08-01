import Foundation
import XCTest
@testable import Zap

/// Which decoder bytes are sent to, and what happens when they're refused before
/// either one runs. The SVG render itself drives a `WKWebView` and stays on
/// `UNJAILED.md §9`'s manual list — the *routing* to it does not.
final class IconImportTests: XCTestCase {

    private func data(_ string: String) -> Data { Data(string.utf8) }

    // MARK: Routing

    func testSVGMarkupRoutesToTheRasteriser() {
        XCTAssertEqual(IconImport.route(for: data("<svg xmlns=\"http://www.w3.org/2000/svg\"/>")), .svg)
        XCTAssertEqual(IconImport.route(for: data("<?xml version=\"1.0\"?><svg></svg>")), .svg)
    }

    func testBitmapBytesRouteToImageIO() {
        // PNG magic.
        XCTAssertEqual(IconImport.route(for: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])),
                       .bitmap)
    }

    /// Neither decoder is asked about something that isn't either — ImageIO gets
    /// it and refuses, which is the same answer it gave before SVG existed.
    func testUnrecognisedBytesRouteToImageIO() {
        XCTAssertEqual(IconImport.route(for: data("just some words")), .bitmap)
        XCTAssertEqual(IconImport.route(for: Data()), .bitmap)
    }

    /// The extension is not consulted anywhere in this path (§6.1), so a file that
    /// merely mentions SVG is a bitmap candidate like anything else.
    func testRoutingIgnoresWhatAFileIsCalled() {
        XCTAssertEqual(IconImport.route(for: data("this file is called icon.svg")), .bitmap)
    }

    func testOversizeDataIsRefusedBeforeEitherDecoder() {
        let tooBig = IconImageValidator.Limits.maximumSourceBytes + 1
        // Byte for byte an SVG, and still refused: the size gate runs first, so a
        // decompression bomb never reaches the sniffer, let alone a decoder.
        var svg = data("<svg>")
        svg.append(Data(repeating: 0x20, count: tooBig - svg.count))
        XCTAssertEqual(IconImport.route(for: svg), .tooLarge(bytes: tooBig))
    }

    // MARK: Importing

    func testOversizeDataFailsWithTheSizeRejection() async {
        let tooBig = IconImageValidator.Limits.maximumSourceBytes + 1
        let result = await IconImport.image(from: Data(repeating: 0, count: tooBig))
        XCTAssertEqual(result.failureValue, .fileTooLarge(bytes: tooBig))
    }

    func testNonImageBytesStillFailAsUnreadable() async {
        let result = await IconImport.image(from: data("not an image, not markup"))
        XCTAssertEqual(result.failureValue, .unreadable)
    }

    func testAMissingFileIsUnreadable() async {
        let missing = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).png")
        let result = await IconImport.image(contentsOf: missing)
        XCTAssertEqual(result.failureValue, .unreadable)
    }

    func testABitmapFileImportsThroughTheSamePath() async throws {
        let directory = IconTestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = IconTestSupport.writePNG(width: 512, height: 512,
                                           to: directory.appendingPathComponent("icon.png"))

        let image = try XCTUnwrap(await IconImport.image(contentsOf: url).successValue)
        XCTAssertEqual(image.width, 512)
    }

    // MARK: Rejection surface

    /// A render failure has to carry the rasteriser's own reason: "took too long"
    /// and "came back blank" are different things to tell someone, and none of the
    /// ImageIO-shaped rejections can say either.
    func testSVGRenderFailureCarriesTheReason() {
        for error in [SVGRasterizer.RasterizeError.timedOut, .snapshotFailed, .notSVG] {
            let rejection = IconImageValidator.Rejection.svgNotRendered(reason: error.message)
            XCTAssertEqual(rejection.message, error.message)
            XCTAssertFalse(rejection.message.isEmpty)
        }
    }
}
