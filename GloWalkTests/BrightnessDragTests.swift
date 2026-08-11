import XCTest
@testable import GloWalk

final class BrightnessDragTests: XCTestCase {
    func testSegmentFromBrightness() {
        XCTAssertEqual(BrightnessDrag.segment(brightness: 1.0), 10)
        XCTAssertEqual(BrightnessDrag.segment(brightness: 0.72), 7)
        XCTAssertEqual(BrightnessDrag.segment(brightness: 0.1), 1)
        XCTAssertEqual(BrightnessDrag.segment(brightness: 0.0), 0)
    }

    func testLevelFromSegment() {
        XCTAssertEqual(BrightnessDrag.level(segment: 10), 1.0, accuracy: 0.0001)
        XCTAssertEqual(BrightnessDrag.level(segment: 3), 0.3, accuracy: 0.0001)
        XCTAssertEqual(BrightnessDrag.level(segment: 0), 0.0, accuracy: 0.0001)
    }

    func testSegmentFromOffset() {
        XCTAssertEqual(BrightnessDrag.segment(forOffset: -200, topOffset: -200, bottomOffset: 100), 10)
        XCTAssertEqual(BrightnessDrag.segment(forOffset: 100, topOffset: -200, bottomOffset: 100), 0)
        XCTAssertEqual(BrightnessDrag.segment(forOffset: -50, topOffset: -200, bottomOffset: 100), 5)
        XCTAssertEqual(BrightnessDrag.segment(forOffset: 500, topOffset: -200, bottomOffset: 100), 0)
    }

    func testSlotYFromSegment() {
        XCTAssertEqual(BrightnessDrag.slotY(segment: 10, topY: 0, bottomY: 600), 0)
        XCTAssertEqual(BrightnessDrag.slotY(segment: 0, topY: 0, bottomY: 600), 600)
        XCTAssertEqual(BrightnessDrag.slotY(segment: 5, topY: 0, bottomY: 600), 300)
    }
}
