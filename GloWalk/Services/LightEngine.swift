import Foundation

@MainActor
final class LightEngine: ObservableObject {
    @Published var targetBrightness: Double = 0.7
    @Published var ambientFactorActive: Bool = true
    @Published var postureFactorActive: Bool = true
    @Published var screenFactorActive: Bool = true
    @Published var darkAdaptationActive: Bool = true
    @Published var moonFactorActive: Bool = true
    @Published var weatherFactorActive: Bool = true
    @Published var factorDetails = FactorDetails()
    @Published var batterySaverCap: Double = 1.0

    private var manualOffset: Double = 0.0
    private var sessionStartTime: Date?

    struct FactorDetails {
        var moonPhaseName: String = ""
        var weatherCondition: String = ""
        var ambientDelta: Int = 0
        var postureDelta: Int = 0
        var screenDelta: Int = 0
        var darkDelta: Int = 0
        var moonDelta: Int = 0
        var weatherDelta: Int = 0
    }

    // MARK: - Signal Weights

    private let wAmbient: Double = 0.40
    private let wPosture: Double = 0.25
    private let wScreen:  Double = 0.10
    private let wDark:    Double = 0.10
    private let wMoon:    Double = 0.10
    private let wWeather: Double = 0.05

    // MARK: - Update

    func update(sensors: SensorSnapshot) {
        if sessionStartTime == nil { sessionStartTime = Date() }

        let rawAmbientSignal = 1.0 - sensors.ambientLight
        let rawPostureSignal = postureScore(pitch: sensors.devicePitch, roll: sensors.deviceRoll)
        let rawScreenSignal = sensors.screenBrightness * 0.5
        let adaptMinutes = sensors.darkAdaptationMinutes
        let rawAdaptSignal = min(adaptMinutes / 30.0, 1.0) * 0.3

        let rawMoonSignal = sensors.moonIllumination * 0.3
        let rawWeatherSignal: Double = {
            guard let w = sensors.weather else { return 0 }
            switch w.lowercased() {
            case "rain", "drizzle", "thunderstorm": return 0.15
            case "snow":                          return 0.25
            default:                              return 0.0
            }
        }()

        // Apply toggles — inactive factors use neutral values
        let ambientSignal = ambientFactorActive ? rawAmbientSignal : 1.0
        let postureSignal = postureFactorActive ? rawPostureSignal : 1.0
        let screenSignal  = screenFactorActive  ? rawScreenSignal  : 0.0
        let adaptSignal   = darkAdaptationActive ? rawAdaptSignal   : 0.0
        let moonSignal    = moonFactorActive     ? rawMoonSignal    : 0.0
        let weatherSignal = weatherFactorActive  ? rawWeatherSignal : 0.0

        // Compute base brightness with all active factors
        let weighted = ambientSignal * wAmbient
                     + postureSignal * wPosture
                     + screenSignal * wScreen
                     + (1.0 - adaptSignal) * wDark
                     + (1.0 - moonSignal) * wMoon
                     + (1.0 + weatherSignal) * wWeather

        let denom = max(wAmbient + postureSignal * wPosture + wScreen + wDark + wMoon + wWeather, 0.01)
        let base = weighted / denom
        targetBrightness = min(max(base + manualOffset, 0.1), batterySaverCap)

        // Proportional gap attribution: each factor's share of the brightness
        // deviation from neutral baseline. Shares sum to (neutral - base) × 100%.
        // Positive = factor pushes brightness up, negative = pushes down.
        let neutralBase = (1.0 * wAmbient + 1.0 * wPosture + 0.0 * wScreen
                         + 1.0 * wDark + 1.0 * wMoon + 1.0 * wWeather)
                        / max(wAmbient + 1.0 * wPosture + wScreen + wDark + wMoon + wWeather, 0.01)
        let gap = neutralBase - base  // positive = factors reduced brightness from neutral

        // Deviation of each factor's contribution from neutral (same units as weighted sum)
        let ambDev  = (1.0 - ambientSignal) * wAmbient
        let posDev  = (1.0 - postureSignal) * wPosture
        let scrDev  = (0.0 - screenSignal)  * wScreen
        let darkDev = (0.0 - adaptSignal)   * wDark   // neutral adapt=0 (no dimming)
        let moonDev = (0.0 - moonSignal)    * wMoon   // neutral moon=0 (no dimming)
        // Actually: neutral = (1.0-0)*wDark = 1.0*wDark, current = (1.0-adapt)*wDark
        // dev = neutral - current = 1.0*wDark - (1.0-adapt)*wDark = adapt*wDark
        // Recalculate correctly:
        let darkDev2 = adaptSignal * wDark
        let moonDev2 = moonSignal * wMoon
        let weathDev = weatherSignal * wWeather

        let totalDev = abs(ambDev) + abs(posDev) + abs(scrDev)
                     + abs(darkDev2) + abs(moonDev2) + abs(weathDev)

        let ambDelta  = gapShare(gap: gap, dev: ambDev,   total: totalDev)
        let posDelta  = gapShare(gap: gap, dev: posDev,   total: totalDev)
        let scrDelta  = gapShare(gap: gap, dev: scrDev,   total: totalDev)
        let darkDelta = gapShare(gap: gap, dev: -darkDev2, total: totalDev)  // negative: dims
        let moonDelta = gapShare(gap: gap, dev: -moonDev2, total: totalDev)  // negative: dims
        let weathDelta = gapShare(gap: gap, dev: weathDev, total: totalDev)  // positive: boosts

        updateFactorDetails(sensors: sensors,
                            ambDelta: ambDelta, posDelta: posDelta, scrDelta: scrDelta,
                            darkDelta: darkDelta, moonDelta: moonDelta, weathDelta: weathDelta)
    }

    /// Attribute a share of the brightness gap to one factor.
    /// Positive = factor boosts brightness; negative = dims.
    private func gapShare(gap: Double, dev: Double, total: Double) -> Int {
        guard total > 0.0001 else { return 0 }
        return Int(round(gap * dev / total * 100))
    }

    // MARK: - Posture

    private func postureScore(pitch: Double, roll: Double) -> Double {
        let pitchOK = pitch >= 30 && pitch <= 60
        let rollOK  = abs(roll) <= 15
        if pitchOK && rollOK { return 1.0 }
        let p = pitch < 30 ? pitch / 30 : max(0, (90 - pitch) / 30)
        let r = rollOK ? 1.0 : max(0, (45 - abs(roll)) / 30)
        return p * r
    }

    // MARK: - Factor Details for HUD

    private func updateFactorDetails(sensors: SensorSnapshot,
                                      ambDelta: Int, posDelta: Int, scrDelta: Int,
                                      darkDelta: Int, moonDelta: Int, weathDelta: Int) {
        factorDetails.ambientDelta = ambDelta
        factorDetails.postureDelta = posDelta
        factorDetails.screenDelta = scrDelta
        factorDetails.darkDelta = darkDelta
        factorDetails.moonDelta = moonDelta
        factorDetails.weatherDelta = weathDelta
        factorDetails.moonPhaseName = moonName(sensors.moonIllumination)
        if let w = sensors.weather {
            factorDetails.weatherCondition = weatherLabel(w)
        }
    }

    private func moonName(_ i: Double) -> String { L10n.moonPhaseName(illumination: i) }
    private func weatherLabel(_ c: String) -> String { L10n.weatherLabel(c) }

    // MARK: - Manual Override

    func setManualOffset(_ offset: Double) { manualOffset = min(max(offset, -0.3), 0.3) }
    func resetManualOffset() { manualOffset = 0.0 }

    // MARK: - Factor Toggles

    func toggleAmbientFactor()  { ambientFactorActive.toggle() }
    func togglePostureFactor()  { postureFactorActive.toggle() }
    func toggleScreenFactor()   { screenFactorActive.toggle() }
    func toggleDarkFactor()     { darkAdaptationActive.toggle() }
    func toggleMoonFactor()     { moonFactorActive.toggle() }
    func toggleWeatherFactor()  { weatherFactorActive.toggle() }

    // MARK: - Safety Fallback

    func enterSafetyFallback() { targetBrightness = 1.0 }
    func resumeFromFallback(completion: @escaping (Double) -> Void) { completion(targetBrightness) }
}

// MARK: - Sensor Snapshot

struct SensorSnapshot {
    let ambientLight: Double
    let devicePitch: Double
    let deviceRoll: Double
    let screenBrightness: Double
    let isWalking: Bool
    let moonIllumination: Double
    let weather: String?
    let darkAdaptationMinutes: Double
}