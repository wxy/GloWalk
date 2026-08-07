import XCTest
@testable import GloWalk

final class PosterGeneratorTests: XCTestCase {

    private func date(hour: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 7,
                                                    hour: hour))!
    }

    func testNightHoursShowMoonPhaseImage() {
        // Night rule matches the HUD celestial indicator: 18:00–05:59.
        for hour in [18, 19, 23, 0, 3, 5] {
            XCTAssertEqual(PosterGenerator.celestialImageName(for: date(hour: hour),
                                                              moonPhase: "waxing_gibbous"),
                           "waxing_gibbous",
                           "Hour \(hour) should show the moon phase")
        }
    }

    func testDayHoursShowSunImage() {
        for hour in [6, 8, 12, 17] {
            XCTAssertEqual(PosterGenerator.celestialImageName(for: date(hour: hour),
                                                              moonPhase: "full_moon"),
                           "sun",
                           "Hour \(hour) should show the sun")
        }
    }
}
