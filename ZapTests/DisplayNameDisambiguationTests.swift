import XCTest
@testable import Zap

/// Label generation for the per-display scope pickers: two monitors that report
/// the same `localizedName` must still get distinct picker labels.
final class DisplayNameDisambiguationTests: XCTestCase {

    /// AppKit global coordinates, so y grows upward: larger midY is physically higher.
    private func rect(x: CGFloat, y: CGFloat) -> CGRect {
        CGRect(x: x, y: y, width: 100, height: 50)
    }

    func testUniqueNamesAreUnchanged() {
        let displays = [
            (name: "Built-in Retina Display", frame: rect(x: 0, y: 0)),
            (name: "DELL U2723QE", frame: rect(x: 200, y: 0))
        ]

        XCTAssertEqual(
            ScreenIdentity.disambiguatedNames(displays),
            ["Built-in Retina Display", "DELL U2723QE"])
    }

    func testTwoIdenticalSideBySideGetLeftAndRightRegardlessOfInputOrder() {
        let left = rect(x: 0, y: 0)
        let right = rect(x: 200, y: 0)

        XCTAssertEqual(
            ScreenIdentity.disambiguatedNames([(name: "DELL", frame: left), (name: "DELL", frame: right)]),
            ["DELL (left)", "DELL (right)"])
        XCTAssertEqual(
            ScreenIdentity.disambiguatedNames([(name: "DELL", frame: right), (name: "DELL", frame: left)]),
            ["DELL (right)", "DELL (left)"])
    }

    func testTwoIdenticalStackedGetTopAndBottom() {
        // The display at y=200 has the larger midY, so it is physically on top.
        let bottom = rect(x: 0, y: 0)
        let top = rect(x: 0, y: 200)

        XCTAssertEqual(
            ScreenIdentity.disambiguatedNames([(name: "DELL", frame: bottom), (name: "DELL", frame: top)]),
            ["DELL (bottom)", "DELL (top)"])
        XCTAssertEqual(
            ScreenIdentity.disambiguatedNames([(name: "DELL", frame: top), (name: "DELL", frame: bottom)]),
            ["DELL (top)", "DELL (bottom)"])
    }

    func testThreeIdenticalAreNumberedInReadingOrder() {
        // Input deliberately out of position order; reading order is by midX
        // ascending: Q (midX 50), R (midX 200), P (midX 350).
        let p = rect(x: 300, y: 0)
        let q = rect(x: 0, y: 0)
        let r = rect(x: 150, y: 0)

        XCTAssertEqual(
            ScreenIdentity.disambiguatedNames([
                (name: "DELL", frame: p),
                (name: "DELL", frame: q),
                (name: "DELL", frame: r)
            ]),
            ["DELL (3)", "DELL (1)", "DELL (2)"])
    }

    func testThreeIdenticalBreakMidXTiesWithHigherDisplayFirst() {
        // B and A share midX; reading order puts the higher one first.
        let a = rect(x: 0, y: 0)
        let b = rect(x: 0, y: 200)
        let c = rect(x: 200, y: 0)

        XCTAssertEqual(
            ScreenIdentity.disambiguatedNames([
                (name: "DELL", frame: a),
                (name: "DELL", frame: b),
                (name: "DELL", frame: c)
            ]),
            ["DELL (2)", "DELL (1)", "DELL (3)"])
    }

    func testMixedGroupLeavesUniqueNameUnchanged() {
        let displays = [
            (name: "Studio Display", frame: rect(x: 400, y: 0)),
            (name: "DELL", frame: rect(x: 0, y: 0)),
            (name: "DELL", frame: rect(x: 200, y: 0))
        ]

        XCTAssertEqual(
            ScreenIdentity.disambiguatedNames(displays),
            ["Studio Display", "DELL (left)", "DELL (right)"])
    }

    func testIdenticalCentersFallBackToNumbering() {
        let mirrored = rect(x: 0, y: 0)

        XCTAssertEqual(
            ScreenIdentity.disambiguatedNames([
                (name: "DELL", frame: mirrored),
                (name: "DELL", frame: mirrored)
            ]),
            ["DELL (1)", "DELL (2)"])
    }
}
