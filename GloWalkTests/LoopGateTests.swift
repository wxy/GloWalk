import XCTest
@testable import GloWalk

final class LoopGateTests: XCTestCase {
    func testActiveInWalkingPosture() {
        let g = LoopGate(pitchDeg: 45, isOccluded: false, isDaylight: false)
        XCTAssertTrue(g.isActive)
    }
    func testFrozenWhenPhoneRaised() {
        let g = LoopGate(pitchDeg: 10, isOccluded: false, isDaylight: false)
        XCTAssertFalse(g.isActive)
    }
    func testFrozenWhenOccludedOrDaylight() {
        XCTAssertFalse(LoopGate(pitchDeg: 45, isOccluded: true, isDaylight: false).isActive)
        XCTAssertFalse(LoopGate(pitchDeg: 45, isOccluded: false, isDaylight: true).isActive)
    }
}
