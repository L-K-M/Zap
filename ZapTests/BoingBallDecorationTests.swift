import XCTest
@testable import Zap

final class BoingBallDecorationTests: XCTestCase {

    private let panel = CGSize(width: 400, height: 160)

    func testBallOccupiesTheCorner() {
        let center = BoingBallDecoration.center(in: panel, position: .topTrailing,
                                                cornerRadius: 0, radius: 50)
        // The centre sits within one radius of both the top and trailing edges, so
        // the disc overshoots the corner and the clip trims it flush — a corner
        // medallion, not a dot floating inside the panel.
        XCTAssertLessThan(center.y, 50)
        XCTAssertGreaterThan(center.x, panel.width - 50)
        // …while staying mostly inside: the centre itself is within the panel.
        XCTAssertGreaterThan(center.y, 0)
        XCTAssertLessThan(center.x, panel.width)
    }

    func testLeadingMirrorsTrailing() {
        let trailing = BoingBallDecoration.center(in: panel, position: .topTrailing,
                                                  cornerRadius: 18, radius: 50)
        let leading = BoingBallDecoration.center(in: panel, position: .topLeading,
                                                 cornerRadius: 18, radius: 50)
        XCTAssertEqual(leading.x, panel.width - trailing.x, accuracy: 0.0001)
        XCTAssertEqual(leading.y, trailing.y, accuracy: 0.0001)
    }

    func testRounderCornersPushTheBallInward() {
        let sharp = BoingBallDecoration.center(in: panel, position: .topTrailing,
                                               cornerRadius: 0, radius: 50)
        let round = BoingBallDecoration.center(in: panel, position: .topTrailing,
                                               cornerRadius: 64, radius: 50)
        // A deeper rounding eats more of the corner, so the ball steps further in
        // (down and away from the trailing edge) to stay clear of the cut.
        XCTAssertGreaterThan(round.y, sharp.y)
        XCTAssertLessThan(round.x, sharp.x)
    }

    func testSphereBitmapMatchesRequestedPixelSize() {
        let bitmap = BoingBallDecoration.renderSphere(pixelDiameter: 64, antialiased: true)
        XCTAssertEqual(bitmap?.width, 64)
        XCTAssertEqual(bitmap?.height, 64)
    }

    func testPixelatedBitmapMatchesRequestedPixelSize() {
        let bitmap = BoingBallDecoration.renderSphere(pixelDiameter: 96, antialiased: false)
        XCTAssertEqual(bitmap?.width, 96)
        XCTAssertEqual(bitmap?.height, 96)
    }

    func testSphereBitmapRejectsDegenerateSize() {
        XCTAssertNil(BoingBallDecoration.renderSphere(pixelDiameter: 0, antialiased: true))
    }
}
