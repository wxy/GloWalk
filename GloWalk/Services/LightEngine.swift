import Foundation

@MainActor
final class LightEngine: ObservableObject {
    @Published var targetBrightness: Double = 0.7
    @Published var moonFactorActive: Bool = true
    @Published var weatherFactorActive: Bool = true
    @Published var darkAdaptationActive: Bool = false
    @Published var factorDetails = FactorDetails()
    /// When < 1.0, caps max brightness for low-battery power saving
    @Published var batterySaverCap: Double = 1.0

    private var manualOffset: Double = 0.0
    private var sessionStartTime: Date?

    struct FactorDetails {
        var moonPhaseName: String = ""
        var moonEffectPercent: Int = 0
        var weatherCondition: String = ""
        var weatherEffectPercent: Int = 0
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

        let ambientSignal = 1.0 - sensors.ambientLight
        let postureSignal = postureScore(pitch: sensors.devicePitch, roll: sensors.deviceRoll)
        let screenSignal = sensors.screenBrightness * 0.5
        let adaptMinutes = sensors.darkAdaptationMinutes
        let adaptSignal = min(adaptMinutes / 30.0, 1.0) * 0.3
        darkAdaptationActive = adaptMinutes > 5.0

        let moonSignal = moonFactorActive ? sensors.moonIllumination * 0.3 : 0.0
        let weatherSignal: Double = {
            guard weatherFactorActive, let w = sensors.weather else { return 0 }
            switch w.lowercased() {
            case "rain", "drizzle", "thunderstorm": return 0.15
            case "snow":                          return 0.25
            default:                              return 0.0
            }
        }()

        let weighted = ambientSignal * wAmbient
                     + postureSignal * wPosture
                     + screenSignal * wScreen
                     + (1.0 - adaptSignal) * wDark
                     + (1.0 - moonSignal) * wMoon
                     + (1.0 + weatherSignal) * wWeather

        let base = weighted / max(
            wAmbient + postureSignal * wPosture + wScreen + wDark + wMoon + wWeather, 0.01
        )
        targetBrightness = min(max(base + manualOffset, 0.1), batterySaverCap)

        updateFactorDetails(sensors: sensors, moonSignal: moonSignal, weatherSignal: weatherSignal)
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
                                      moonSignal: Double,
                                      weatherSignal: Double) {
        factorDetails.moonEffectPercent = Int(round(-moonSignal * 100))
        factorDetails.moonPhaseName = moonName(sensors.moonIllumination)
        if let w = sensors.weather {
            factorDetails.weatherCondition = weatherLabel(w)
            factorDetails.weatherEffectPercent = Int(round(weatherSignal * 100))
        }
    }

    private func moonName(_ i: Double) -> String { L10n.moonPhaseName(illumination: i) }
    private func weatherLabel(_ c: String) -> String { L10n.weatherLabel(c) }

    // MARK: - Manual Override

    func setManualOffset(_ offset: Double) { manualOffset = min(max(offset, -0.3), 0.3) }
    func resetManualOffset() { manualOffset = 0.0 }

    // MARK: - Factor Toggles (per-walk)

    func toggleMoonFactor() { moonFactorActive.toggle() }
    func toggleWeatherFactor() { weatherFactorActive.toggle() }

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