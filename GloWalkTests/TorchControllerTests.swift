import XCTest
@testable import GloWalk

final class TorchControllerTests: XCTestCase {
    private let levels: [Double] = [0, 0.15, 0.3, 0.45, 0.6, 0.75, 0.9, 1.0]

    func testRaisesLevelWhenMeasuredBelowSetpoint() {
        var c = TorchController(levels: levels, deadband: 0.04, hysteresis: 0.02)
        let out = c.step(setpoint: 0.4, measured: 0.2, active: true)
        XCTAssertEqual(out, 0.15)
    }

    func testHoldsWithinDeadband() {
        var c = TorchController(levels: levels, deadband: 0.04, hysteresis: 0.02)
        XCTAssertEqual(c.step(setpoint: 0.4, measured: 0.41, active: true), 0.0)
    }

    func testDoesNotOscillateAroundSetpoint() {
        var c = TorchController(levels: levels, deadband: 0.04, hysteresis: 0.02)
        _ = c.step(setpoint: 0.4, measured: 0.1, active: true)   // → 0.15
        _ = c.step(setpoint: 0.4, measured: 0.35, active: true)  // 仍在死区
        XCTAssertEqual(c.step(setpoint: 0.4, measured: 0.38, active: true), 0.15)
    }

    func testClampsAtMaxLevel() {
        var c = TorchController(levels: levels, deadband: 0.04, hysteresis: 0.02)
        for _ in 0..<20 {
            _ = c.step(setpoint: 1.0, measured: 0.0, active: true)
        }
        XCTAssertEqual(c.step(setpoint: 1.0, measured: 0.0, active: true), 1.0)
    }

    func testFreezesWhenInactive() {
        var c = TorchController(levels: levels, deadband: 0.04, hysteresis: 0.02)
        _ = c.step(setpoint: 0.4, measured: 0.2, active: true)   // → 0.15
        XCTAssertEqual(c.step(setpoint: 0.4, measured: 0.9, active: false), 0.15)
    }
}
