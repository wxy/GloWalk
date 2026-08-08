import XCTest
@testable import GloWalk

final class LoopGateTests: XCTestCase {
    func testActiveInWalkingPosture() {
        let g = LoopGate(pitchDeg: 45, isOccluded: false, isDaylight: false, isTorchPaused: false)
        XCTAssertTrue(g.isActive)
    }
    func testFrozenWhenPhoneRaised() {
        let g = LoopGate(pitchDeg: 10, isOccluded: false, isDaylight: false, isTorchPaused: false)
        XCTAssertFalse(g.isActive)
    }
    func testFrozenWhenOccludedOrPausedOrDaylight() {
        XCTAssertFalse(LoopGate(pitchDeg: 45, isOccluded: true, isDaylight: false, isTorchPaused: false).isActive)
        XCTAssertFalse(LoopGate(pitchDeg: 45, isOccluded: false, isDaylight: false, isTorchPaused: true).isActive)
        XCTAssertFalse(LoopGate(pitchDeg: 45, isOccluded: false, isDaylight: true, isTorchPaused: false).isActive)
    }
}
