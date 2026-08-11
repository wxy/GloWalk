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

    func testSegmentFromPosition() {
        XCTAssertEqual(BrightnessDrag.segment(forY: 0, topY: 0, bottomY: 600), 10)
        XCTAssertEqual(BrightnessDrag.segment(forY: 600, topY: 0, bottomY: 600), 0)
        XCTAssertEqual(BrightnessDrag.segment(forY: 300, topY: 0, bottomY: 600), 5)
        // 拖出范围后钳制：高于顶部=全亮，低于亮度条=关闭。
        XCTAssertEqual(BrightnessDrag.segment(forY: -50, topY: 0, bottomY: 600), 10)
        XCTAssertEqual(BrightnessDrag.segment(forY: 900, topY: 0, bottomY: 600), 0)
    }

    func testSlotYFromSegment() {
        XCTAssertEqual(BrightnessDrag.slotY(segment: 10, topY: 0, bottomY: 600), 0)
        XCTAssertEqual(BrightnessDrag.slotY(segment: 0, topY: 0, bottomY: 600), 600)
        XCTAssertEqual(BrightnessDrag.slotY(segment: 5, topY: 0, bottomY: 600), 300)
    }
}
