import XCTest
@testable import Zap

/// Geometry tests for the icon-row edge fade. The row auto-scrolls to centre the
/// selected icon (clamping at both ends), so the fade is a pure function of the
/// selection and layout — which is exactly what these exercise.
///
/// Layout used by most cases: 96pt cells, 12pt spacing (so each step is 108pt).
final class EdgeFadeTests: XCTestCase {

    private let accuracy: CGFloat = 1e-6

    // MARK: No overflow

    func testRowThatFitsHasNoFade() {
        // 3 icons (312pt) inside a 1000pt viewport — nothing is hidden.
        let fade = EdgeFade.forIconRow(selectedIndex: 1, count: 3, cellWidth: 96,
                                       spacing: 12, viewport: 1000, fadeWidth: 80)
        XCTAssertEqual(fade, .none)
    }

    func testEmptyOrDegenerateInputsHaveNoFade() {
        XCTAssertEqual(EdgeFade.forIconRow(selectedIndex: 0, count: 0, cellWidth: 96,
                                           spacing: 12, viewport: 1000, fadeWidth: 80), .none)
        XCTAssertEqual(EdgeFade.forIconRow(selectedIndex: 0, count: 5, cellWidth: 96,
                                           spacing: 12, viewport: 0, fadeWidth: 80), .none)
    }

    // MARK: Which edge fades (the reported bug)

    func testFirstSelectionFadesOnlyTheRight() {
        // Scrolled hard left: nothing hidden on the left, everything spills right.
        let fade = EdgeFade.forIconRow(selectedIndex: 0, count: 20, cellWidth: 96,
                                       spacing: 12, viewport: 1000, fadeWidth: 80)
        XCTAssertEqual(fade.leading, 0, accuracy: accuracy)
        XCTAssertEqual(fade.trailing, 1, accuracy: accuracy)
    }

    func testLastSelectionFadesOnlyTheLeft() {
        // Scrolled hard right: nothing hidden on the right — the side that used to
        // keep fading. This is the case the user reported.
        let fade = EdgeFade.forIconRow(selectedIndex: 19, count: 20, cellWidth: 96,
                                       spacing: 12, viewport: 1000, fadeWidth: 80)
        XCTAssertEqual(fade.leading, 1, accuracy: accuracy)
        XCTAssertEqual(fade.trailing, 0, accuracy: accuracy)
    }

    func testMiddleSelectionFadesBothEdges() {
        let fade = EdgeFade.forIconRow(selectedIndex: 10, count: 20, cellWidth: 96,
                                       spacing: 12, viewport: 1000, fadeWidth: 80)
        XCTAssertGreaterThan(fade.leading, 0)
        XCTAssertGreaterThan(fade.trailing, 0)
    }

    // MARK: Exact ramp values

    /// 5 icons (528pt) in a 480pt viewport ⇒ 48pt of scroll, 80pt ramp.
    /// The selected centre, clamped to that 48pt range, yields predictable fades.
    func testPartialFadeRampValues() {
        func fade(_ index: Int) -> EdgeFade {
            EdgeFade.forIconRow(selectedIndex: index, count: 5, cellWidth: 96,
                                spacing: 12, viewport: 480, fadeWidth: 80)
        }
        // index 0 → scrolled 0/48:  no left fade, 48/80 of a right fade.
        XCTAssertEqual(fade(0).leading, 0, accuracy: accuracy)
        XCTAssertEqual(fade(0).trailing, 0.6, accuracy: accuracy)
        // index 2 → scrolled 24/48:  symmetric half-ramp on both sides.
        XCTAssertEqual(fade(2).leading, 0.3, accuracy: accuracy)
        XCTAssertEqual(fade(2).trailing, 0.3, accuracy: accuracy)
        // index 4 → scrolled 48/48:  48/80 of a left fade, no right fade.
        XCTAssertEqual(fade(4).leading, 0.6, accuracy: accuracy)
        XCTAssertEqual(fade(4).trailing, 0, accuracy: accuracy)
    }

    // MARK: Monotonicity

    func testFadeShiftsFromRightToLeftAsSelectionAdvances() {
        let fades = (0..<20).map {
            EdgeFade.forIconRow(selectedIndex: $0, count: 20, cellWidth: 96,
                                spacing: 12, viewport: 1000, fadeWidth: 80)
        }
        for (a, b) in zip(fades, fades.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b.leading, a.leading)   // left fade only grows
            XCTAssertLessThanOrEqual(b.trailing, a.trailing)    // right fade only shrinks
        }
    }

    // MARK: Ramp width

    func testRampInsetIsFadeWidthOverViewport() {
        let fade = EdgeFade.forIconRow(selectedIndex: 0, count: 20, cellWidth: 96,
                                       spacing: 12, viewport: 480, fadeWidth: 80)
        XCTAssertEqual(fade.inset, 80.0 / 480.0, accuracy: accuracy)
    }

    func testRampIsClampedToAThirdOfTheViewport() {
        // An absurd fade width can't exceed a third of the viewport.
        let fade = EdgeFade.forIconRow(selectedIndex: 0, count: 5, cellWidth: 96,
                                       spacing: 12, viewport: 480, fadeWidth: 10_000)
        XCTAssertEqual(fade.inset, 1.0 / 3.0, accuracy: accuracy)
        // ramp = 160, so index 0's right fade is 48/160.
        XCTAssertEqual(fade.trailing, 48.0 / 160.0, accuracy: accuracy)
    }

    // MARK: Out-of-range selection

    func testSelectionIndexIsClampedIntoRange() {
        let past = EdgeFade.forIconRow(selectedIndex: 99, count: 5, cellWidth: 96,
                                       spacing: 12, viewport: 480, fadeWidth: 80)
        let last = EdgeFade.forIconRow(selectedIndex: 4, count: 5, cellWidth: 96,
                                       spacing: 12, viewport: 480, fadeWidth: 80)
        XCTAssertEqual(past, last)

        let negative = EdgeFade.forIconRow(selectedIndex: -3, count: 5, cellWidth: 96,
                                           spacing: 12, viewport: 480, fadeWidth: 80)
        let first = EdgeFade.forIconRow(selectedIndex: 0, count: 5, cellWidth: 96,
                                        spacing: 12, viewport: 480, fadeWidth: 80)
        XCTAssertEqual(negative, first)
    }
}
