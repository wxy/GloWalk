import XCTest
@testable import GloWalk

@MainActor
final class LightEngineTests: XCTestCase {

    var engine: LightEngine!

    override func setUp() {
        engine = LightEngine()
    }

    // MARK: - Weather Boost

    func testRainBoostsBrightness() {
        let withRain = makeSnapshot(ambient: 0.5, posture: 1.0, weather: "rain")
        let noWeather = makeSnapshot(ambient: 0.5, posture: 1.0, weather: nil)

        engine.update(sensors: withRain)
        let rainBrightness = engine.targetBrightness

        engine.update(sensors: noWeather)
        let dryBrightness = engine.targetBrightness

        // Rain should produce higher brightness than dry
        XCTAssertGreaterThan(rainBrightness, dryBrightness,
                             "Rain should boost brightness for safety")
    }

    func testSnowBoostsMoreThanRain() {
        let rain = makeSnapshot(ambient: 0.5, posture: 1.0, weather: "rain")
        let snow = makeSnapshot(ambient: 0.5, posture: 1.0, weather: "snow")

        engine.update(sensors: rain)
        let rainB = engine.targetBrightness

        engine.update(sensors: snow)
        let snowB = engine.targetBrightness

        // Snow should boost more than rain
        XCTAssertGreaterThan(snowB, rainB,
                             "Snow should provide a larger brightness boost than rain")
    }

    func testClearWeatherNoBoost() {
        let clear = makeSnapshot(ambient: 0.5, posture: 1.0, weather: "clear")
        let none = makeSnapshot(ambient: 0.5, posture: 1.0, weather: nil)

        engine.update(sensors: clear)
        let clearB = engine.targetBrightness

        engine.update(sensors: none)
        let noneB = engine.targetBrightness

        XCTAssertEqual(clearB, noneB, accuracy: 0.001,
                       "Clear weather should have no brightness effect")
    }

    // MARK: - Moon Factor

    func testFullMoonReducesBrightness() {
        let full = makeSnapshot(ambient: 0.5, posture: 1.0, moonIllumination: 1.0)
        let new = makeSnapshot(ambient: 0.5, posture: 1.0, moonIllumination: 0.0)

        engine.update(sensors: full)
        let fullB = engine.targetBrightness

        engine.update(sensors: new)
        let newB = engine.targetBrightness

        // Full moon should reduce brightness (more natural light)
        XCTAssertLessThan(fullB, newB,
                          "Full moon should reduce torch brightness")
    }

    func testMoonFactorToggleDisablesMoonSignal() {
        let full = makeSnapshot(ambient: 0.5, posture: 1.0, moonIllumination: 1.0)
        let new = makeSnapshot(ambient: 0.5, posture: 1.0, moonIllumination: 0.0)

        engine.moonFactorActive = true
        engine.update(sensors: full)
        let fullActive = engine.targetBrightness

        engine.moonFactorActive = false
        engine.update(sensors: full)
        let fullInactive = engine.targetBrightness

        engine.moonFactorActive = true
        engine.update(sensors: new)
        let newActive = engine.targetBrightness

        // With moon disabled, full moon brightness should equal new moon brightness
        XCTAssertEqual(fullInactive, newActive, accuracy: 0.001,
                       "Disabling moon factor should neutralize moon effect")
        // With moon enabled, full moon should be dimmer
        XCTAssertLessThan(fullActive, newActive)
    }

    // MARK: - Battery Saver Cap

    func testBatterySaverCapLimitsBrightness() {
        let bright = makeSnapshot(ambient: 0.0, posture: 1.0) // Dark → full brightness

        engine.batterySaverCap = 1.0
        engine.update(sensors: bright)
        let uncapped = engine.targetBrightness

        engine.batterySaverCap = 0.6
        engine.update(sensors: bright)
        let capped = engine.targetBrightness

        XCTAssertLessThanOrEqual(capped, 0.6,
                                 "Battery saver cap should limit max brightness")
        XCTAssertGreaterThan(uncapped, capped,
                             "Uncapped brightness should be higher than capped")
    }

    func testBatteryCapAt80Percent() {
        let bright = makeSnapshot(ambient: 0.0, posture: 1.0)

        engine.batterySaverCap = 0.8
        engine.update(sensors: bright)

        XCTAssertLessThanOrEqual(engine.targetBrightness, 0.8)
    }

    // MARK: - Brightness Floor

    func testBrightnessNeverBelowMinimum() {
        let extreme = makeSnapshot(ambient: 1.0, posture: 0.0, moonIllumination: 1.0)

        // Run multiple updates to ensure floor is respected
        for _ in 0..<10 {
            engine.update(sensors: extreme)
        }

        XCTAssertGreaterThanOrEqual(engine.targetBrightness, 0.1,
                                    "Brightness should never drop below 0.1")
    }

    // MARK: - Posture Signal

    func testIdealPostureGivesFullSignal() {
        let ideal = makeSnapshot(posturePitch: 45, postureRoll: 0, posture: 1.0)
        engine.update(sensors: ideal)
        // Just verify it doesn't crash and produces valid output
        XCTAssertGreaterThan(engine.targetBrightness, 0)
        XCTAssertLessThanOrEqual(engine.targetBrightness, 1.0)
    }

    func testFlatPhoneReducesSignal() {
        let flat = makeSnapshot(posturePitch: 0, postureRoll: 0, posture: 1.0)
        let ideal = makeSnapshot(posturePitch: 45, postureRoll: 0, posture: 1.0)

        engine.update(sensors: flat)
        let flatB = engine.targetBrightness

        engine = LightEngine()
        engine.update(sensors: ideal)
        let idealB = engine.targetBrightness

        // Flat phone (on table) should be dimmer than ideal holding angle
        XCTAssertLessThan(flatB, idealB,
                          "Phone lying flat should produce lower brightness than ideal angle")
    }

    // MARK: - Weather Factor Toggle

    func testWeatherFactorToggle() {
        let rain = makeSnapshot(ambient: 0.5, posture: 1.0, weather: "rain")

        engine.weatherFactorActive = true
        engine.update(sensors: rain)
        let active = engine.targetBrightness

        engine.weatherFactorActive = false
        engine.update(sensors: rain)
        let inactive = engine.targetBrightness

        let clear = makeSnapshot(ambient: 0.5, posture: 1.0, weather: nil)
        engine.weatherFactorActive = true
        engine.update(sensors: clear)
        let clearB = engine.targetBrightness

        // Disabling weather should make rain act like clear weather
        XCTAssertEqual(inactive, clearB, accuracy: 0.001)
        // With weather active, rain should differ from clear
        XCTAssertNotEqual(active, clearB, accuracy: 0.001)
    }

    // MARK: - Factor Details

    func testWeatherFactorDetails() {
        let rain = makeSnapshot(ambient: 0.5, posture: 1.0, weather: "rain")
        engine.update(sensors: rain)

        XCTAssertFalse(engine.factorDetails.weatherCondition.isEmpty)
        XCTAssertNotEqual(engine.factorDetails.weatherEffectPercent, 0)
    }

    func testMoonFactorDetails() {
        let full = makeSnapshot(ambient: 0.5, posture: 1.0, moonIllumination: 1.0)
        engine.update(sensors: full)

        XCTAssertFalse(engine.factorDetails.moonPhaseName.isEmpty)
    }

    // MARK: - Helpers

    private func makeSnapshot(
        ambient: Double = 0.5,
        posturePitch: Double = 45,
        postureRoll: Double = 0,
        posture: Double = 1.0,
        screen: Double = 0.5,
        moonIllumination: Double = 0.5,
        weather: String? = nil,
        darkMinutes: Double = 0
    ) -> SensorSnapshot {
        SensorSnapshot(
            ambientLight: ambient,
            devicePitch: posturePitch,
            deviceRoll: postureRoll,
            screenBrightness: screen,
            isWalking: true,
            moonIllumination: moonIllumination,
            weather: weather,
            darkAdaptationMinutes: darkMinutes
        )
    }
}
