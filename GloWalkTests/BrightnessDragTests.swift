import XCTest
@testable import GloWalk

final class BrightnessDragTests: XCTestCase {
    func testUpDragAddsOneStepPerStepHeight() {
        XCTAssertEqual(BrightnessDrag.stepDelta(translationHeight: -20, stepHeight: 20), 1)
        XCTAssertEqual(BrightnessDrag.stepDelta(translationHeight: -45, stepHeight: 20), 2)
        XCTAssertEqual(BrightnessDrag.stepDelta(translationHeight: -5, stepHeight: 20), 0)
    }

    func testDownDragSubtractsSteps() {
        XCTAssertEqual(BrightnessDrag.stepDelta(translationHeight: 20, stepHeight: 20), -1)
        XCTAssertEqual(BrightnessDrag.stepDelta(translationHeight: 45, stepHeight: 20), -2)
    }

    func testLevelClampsToTenSegments() {
        XCTAssertEqual(BrightnessDrag.level(startSteps: 9, delta: 5), 1.0, accuracy: 0.0001)
        XCTAssertEqual(BrightnessDrag.level(startSteps: 2, delta: -5), 0.1, accuracy: 0.0001)
        XCTAssertEqual(BrightnessDrag.level(startSteps: 3, delta: 0), 0.3, accuracy: 0.0001)
    }

    func testStartStepsFromBrightness() {
        XCTAssertEqual(BrightnessDrag.startSteps(brightness: 0.72), 7)
        XCTAssertEqual(BrightnessDrag.startSteps(brightness: 0.1), 1)
        XCTAssertEqual(BrightnessDrag.startSteps(brightness: 1.0), 10)
    }
}
