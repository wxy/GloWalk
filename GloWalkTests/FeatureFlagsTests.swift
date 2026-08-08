import XCTest
@testable import GloWalk

final class FeatureFlagsTests: XCTestCase {
    func testMeasurementRowFormat() {
        let row = TorchMeasurementLog.row(
            timestamp: Date(timeIntervalSinceReferenceDate: 100),
            torchLevel: 0.5, fullFrame: 0.25, roi: 0.3, pitch: 42, active: true,
            ambient: 0.6)
        let parts = row.split(separator: ",")
        XCTAssertEqual(parts.count, 7)
        XCTAssertEqual(parts[1], "0.500")
        XCTAssertEqual(parts[5], "1")
        XCTAssertEqual(parts[6], "0.6000")
    }
}
