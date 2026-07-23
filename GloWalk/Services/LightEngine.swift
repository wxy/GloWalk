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

        // Proportional gap attribution: each factor's share of the gap from
        // 100% to current brightness. Factors deviate from their "max boost"
        // state. Shares sum exactly to targetBrightness - 100%.
        // All deltas are ≤0 (pull brightness down), weather can be 0.
        let ambShortfall  = (1.0 - ambientSignal) * wAmbient
        let posShortfall  = (1.0 - postureSignal) * wPosture
        let scrShortfall  = screenSignal * wScreen
        let darkShortfall = adaptSignal * wDark
        let moonShortfall = moonSignal * wMoon
        let weathShortfall = (0.25 - weatherSignal) * wWeather  // 0.25 = max weather boost

        let totalShortfall = ambShortfall + posShortfall + scrShortfall
                           + darkShortfall + moonShortfall + weathShortfall
        let gap = 1.0 - base  // gap from 100%

        func attr(_ shortfall: Double) -> Int {
            guard totalShortfall > 0.0001 else { return 0 }
            return -Int(round(shortfall / totalShortfall * gap * 100))
        }

        let ambDelta  = attr(ambShortfall)
        let posDelta  = attr(posShortfall)
        let scrDelta  = attr(scrShortfall)
        let darkDelta = attr(darkShortfall)
        let moonDelta = attr(moonShortfall)
        let weathDelta = attr(weathShortfall)

        updateFactorDetails(sensors: sensors,
                            ambDelta: ambDelta, posDelta: posDelta, scrDelta: scrDelta,
                            darkDelta: darkDelta, moonDelta: moonDelta, weathDelta: weathDelta)
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