import XCTest
@testable import GloWalk

final class MoonPhaseTests: XCTestCase {
    func testKnownNewMoonDate() {
        let date = Date(timeIntervalSince1970: 947192040)
        let result = MoonPhase.current(date: date)
        XCTAssertEqual(result.phase, "new_moon")
        XCTAssertLessThan(result.illumination, 0.05)
    }

    func testNewMoonBrightnessFactor() {
        let factor = MoonPhase.brightnessFactor(illumination: 0.0)
        XCTAssertEqual(factor, 1.0, accuracy: 0.01)
    }

    func testFullMoonBrightnessFactor() {
        let factor = MoonPhase.brightnessFactor(illumination: 1.0)
        XCTAssertEqual(factor, 0.7, accuracy: 0.01)
    }

    func testBrightnessFactorIsBetween07And1() {
        for illum in stride(from: 0.0, through: 1.0, by: 0.1) {
            let factor = MoonPhase.brightnessFactor(illumination: illum)
            XCTAssertGreaterThanOrEqual(factor, 0.7)
            XCTAssertLessThanOrEqual(factor, 1.0)
        }
    }

    func testPhaseCyclesThroughAllPhases() {
        let synodicMonth: TimeInterval = 29.53058867 * 24 * 3600
        let start = Date(timeIntervalSince1970: 947192040)
        let checkPoints: [TimeInterval] = [0, synodicMonth * 0.125, synodicMonth * 0.25,
                                            synodicMonth * 0.375, synodicMonth * 0.5,
                                            synodicMonth * 0.625, synodicMonth * 0.75,
                                            synodicMonth * 0.875]
        let expected = ["new_moon", "waxing_crescent", "first_quarter", "waxing_gibbous",
                        "full_moon", "waning_gibbous", "last_quarter", "waning_crescent"]
        for (offset, exp) in zip(checkPoints, expected) {
            let result = MoonPhase.current(date: start.addingTimeInterval(offset))
            XCTAssertEqual(result.phase, exp)
        }
    }
}
