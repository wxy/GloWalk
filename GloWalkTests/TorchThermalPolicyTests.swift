import XCTest
@testable import GloWalk

final class TorchThermalPolicyTests: XCTestCase {
    func testNominalPassesThrough() {
        XCTAssertEqual(TorchThermalPolicy.cappedLevel(0.9, thermalState: .nominal), 0.9, accuracy: 0.0001)
        XCTAssertEqual(TorchThermalPolicy.cappedLevel(0.9, thermalState: .fair), 0.9, accuracy: 0.0001)
    }

    func testSeriousCapsAtSixtyPercent() {
        XCTAssertEqual(TorchThermalPolicy.cappedLevel(0.9, thermalState: .serious), 0.6, accuracy: 0.0001)
        XCTAssertEqual(TorchThermalPolicy.cappedLevel(0.4, thermalState: .serious), 0.4, accuracy: 0.0001)
    }

    func testCriticalCapsAtThirtyPercent() {
        XCTAssertEqual(TorchThermalPolicy.cappedLevel(0.9, thermalState: .critical), 0.3, accuracy: 0.0001)
        XCTAssertEqual(TorchThermalPolicy.cappedLevel(0.2, thermalState: .critical), 0.2, accuracy: 0.0001)
    }

    func testNeverRaisesTheRequestedLevel() {
        for state in [ProcessInfo.ThermalState.nominal, .fair, .serious, .critical] {
            let capped = TorchThermalPolicy.cappedLevel(0.1, thermalState: state)
            XCTAssertLessThanOrEqual(capped, 0.1)
        }
    }
}
