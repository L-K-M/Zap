import Foundation
import XCTest
@testable import Zap

/// Canned-payload tests, the same shape as `GitHubReleaseTests`.
final class IconifyClientTests: XCTestCase {

    private let host = "https://api.iconify.design"

    private var sets: [String: IconCollection] {
        ["logos": IconCollection(name: "SVG Logos",
                                 license: IconCollection.License(title: "CC0 1.0", url: "https://example.invalid")),
         "mdi": IconCollection(name: "Material Design Icons", license: nil)]
    }

    // MARK: Decoding

    func testDecodesASearchPayload() throws {
        let json = #"{"icons":["logos:safari","mdi:web"],"total":2}"#
        let payload = try JSONDecoder().decode(IconifyClient.SearchPayload.self,
                                               from: Data(json.utf8))
        XCTAssertEqual(payload.icons, ["logos:safari", "mdi:web"])
    }

    func testDecodesCollections() throws {
        let json = """
        {"logos":{"name":"SVG Logos","license":{"title":"CC0 1.0","url":"https://example.invalid"}},
         "mdi":{"name":"Material Design Icons"}}
        """
        let decoded = try JSONDecoder().decode([String: IconCollection].self, from: Data(json.utf8))
        XCTAssertEqual(decoded["logos"]?.license?.title, "CC0 1.0")
        XCTAssertNil(decoded["mdi"]?.license)
    }

    // MARK: Mapping

    func testMapsAnIconIDToAResultWithAttribution() throws {
        let result = try XCTUnwrap(
            IconifyClient.result(forIconID: "logos:safari", sets: sets, host: host))

        XCTAssertEqual(result.id, "iconify:logos:safari")
        XCTAssertEqual(result.providerID, "iconify")
        XCTAssertTrue(result.isVector)
        // §5.4: the credit has to be on the result, or it can't reach the manifest.
        XCTAssertEqual(result.credit, "SVG Logos")
        XCTAssertEqual(result.license, "CC0 1.0")
        XCTAssertNotNil(result.creditURL)
        XCTAssertTrue(result.imageURL.absoluteString.hasPrefix("\(host)/logos/safari.svg"))
    }

    func testRequestsArtworkAtTheMasterSize() throws {
        let result = try XCTUnwrap(
            IconifyClient.result(forIconID: "logos:safari", sets: sets, host: host))
        XCTAssertTrue(result.imageURL.absoluteString
            .contains("height=\(IconImageValidator.Limits.masterLongestEdge)"))
    }

    func testFallsBackToThePrefixWhenTheSetIsUnknown() throws {
        let result = try XCTUnwrap(
            IconifyClient.result(forIconID: "unknown-set:thing", sets: sets, host: host))
        XCTAssertEqual(result.credit, "unknown-set")
        XCTAssertNil(result.license)
    }

    func testASetWithoutALicenceStillProducesAResult() throws {
        let result = try XCTUnwrap(IconifyClient.result(forIconID: "mdi:web", sets: sets, host: host))
        XCTAssertEqual(result.credit, "Material Design Icons")
        XCTAssertNil(result.license)
    }

    func testMalformedIdentifiersAreDropped() {
        for identifier in ["", "nocolon", ":leading", "trailing:", ":"] {
            XCTAssertNil(IconifyClient.result(forIconID: identifier, sets: sets, host: host),
                         "should reject \(identifier)")
        }
    }

    /// An icon name may itself contain a colon-free hyphenated form; only the first
    /// colon separates the set from the name.
    func testOnlyTheFirstColonSplits() throws {
        let result = try XCTUnwrap(
            IconifyClient.result(forIconID: "logos:visual-studio-code", sets: sets, host: host))
        XCTAssertEqual(result.title, "visual studio code")
    }

    // MARK: Provider surface

    func testProviderIsKeylessAndDisclosesWhatItSends() {
        let client = IconifyClient()
        XCTAssertFalse(client.requiresAPIKey)
        // §5.5: the disclosure has to say what leaves the machine.
        XCTAssertTrue(client.disclosure.contains("api.iconify.design"))
        XCTAssertFalse(client.disclosure.isEmpty)
    }

    func testEmptyQueryDoesNotSearch() async {
        // Never send a request for nothing — and never automatically (§5.5).
        let result = await IconifyClient().search(query: "   ", limit: 10)
        XCTAssertEqual(result.successValue?.isEmpty, true)
    }
}
