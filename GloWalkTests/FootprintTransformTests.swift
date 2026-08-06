import XCTest
import SwiftUI
@testable import GloWalk

/// Locks the affine math behind the HUD footprint trail: the glyph is drawn
/// at local (0,0), so the transform must land it centred on `pos` and point
/// its toes along `angle` for both the right and left (mirrored) foot. A
/// regression here used `concatenating` the wrong way round, which translated
/// before rotating and swung every print around the canvas origin — off-screen.
final class FootprintTransformTests: XCTestCase {

    private func assertTransform(_ t: CGAffineTransform,
                                 centersOn pos: CGPoint,
                                 toesPointAlong angle: CGFloat,
                                 file: StaticString = #filePath,
                                 line: UInt = #line) {
        // Glyph centre is local (0,0); the transform must map it onto `pos`.
        let center = CGPoint.zero.applying(t)
        XCTAssertEqual(center.x, pos.x, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(center.y, pos.y, accuracy: 0.001, file: file, line: line)

        // A point at the glyph's intrinsic toe direction must end up along
        // `angle` measured from `pos` — both feet must face the same way; the
        // left foot only mirrors the big-toe side, not the toe direction.
        let toeAngle: CGFloat = -0.7
        let toeDir = CGPoint(x: cos(toeAngle), y: sin(toeAngle))
        let toe = toeDir.applying(t)
        let dir = atan2(toe.y - pos.y, toe.x - pos.x)
        XCTAssertEqual(dir, angle, accuracy: 0.001, file: file, line: line)
    }

    func testRightFootCentersAndFacesAngle() {
        let pos = CGPoint(x: 150, y: 85)
        for angle: CGFloat in [0, 0.8, -1.4, 2.5] {
            let t = ConstellationPathView.footprintTransform(at: pos, angle: angle, isLeft: false)
            assertTransform(t, centersOn: pos, toesPointAlong: angle)
        }
    }

    func testLeftFootCentersAndFacesSameAngle() {
        let pos = CGPoint(x: 150, y: 85)
        for angle: CGFloat in [0, 0.8, -1.4, 2.5] {
            let t = ConstellationPathView.footprintTransform(at: pos, angle: angle, isLeft: true)
            assertTransform(t, centersOn: pos, toesPointAlong: angle)
        }
    }

    func testLeftAndRightFeetDifferOnlyByMirror() {
        // The two feet must be mirror images across the toe-heel axis: same
        // centre, same toe direction, but opposite big-toe sides.
        let pos = CGPoint(x: 100, y: 100)
        let angle: CGFloat = 0.7
        let right = ConstellationPathView.footprintTransform(at: pos, angle: angle, isLeft: false)
        let left = ConstellationPathView.footprintTransform(at: pos, angle: angle, isLeft: true)

        // A point on the big-toe side in the glyph frame maps to opposite
        // sides of the travel axis for the two feet.
        let sidePoint = CGPoint(x: 0, y: -1)
        let rSide = sidePoint.applying(right)
        let lSide = sidePoint.applying(left)
        let rOffset = atan2(rSide.y - pos.y, rSide.x - pos.x) - angle
        let lOffset = atan2(lSide.y - pos.y, lSide.x - pos.x) - angle
        // Offsets measured relative to the toe axis must be opposite signs.
        let normalised = { (a: CGFloat) in
            var v = a.truncatingRemainder(dividingBy: 2 * .pi)
            if v > .pi { v -= 2 * .pi }
            if v < -.pi { v += 2 * .pi }
            return v
        }
        XCTAssertEqual(normalised(rOffset), -normalised(lOffset), accuracy: 0.001)
    }
}
