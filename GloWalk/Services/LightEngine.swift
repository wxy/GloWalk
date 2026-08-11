import Foundation

@MainActor
final class LightEngine: ObservableObject {
    @Published var targetBrightness: Double = 0.7
    @Published var ambientFactorActive: Bool = true
    @Published var postureFactorActive: Bool = true
    @Published var darkAdaptationActive: Bool = true
    @Published var moonFactorActive: Bool = true
    @Published var weatherFactorActive: Bool = true
    @Published var factorDetails = FactorDetails()
    @Published var batterySaverCap: Double = 1.0

    /// Absolute manual brightness override; nil = automatic.
    /// While set, every automatic mechanism (factors, daylight gate, battery
    /// cap) is bypassed and the torch stays exactly at this level.
    private(set) var manualBrightness: Double?
    private var sessionStartTime: Date?

    /// True while the user has a manual brightness override in effect.
    var isManual: Bool { manualBrightness != nil }

    struct FactorDetails {
        var moonPhaseName: String = ""
        var weatherCondition: String = ""
        /// Each factor's share of the total brightness shortfall (0–1, sum ≈ 1
        /// when anything is deducted). Drives the ring-segment coloring so the
        /// displayed deductions reconcile with the actual brightness.
        var ambientShare: Double = 0
        var postureShare: Double = 0
        var darkShare: Double = 0
        var moonShare: Double = 0
        var weatherShare: Double = 0
        var ambientDelta: Int = 0
        var postureDelta: Int = 0
        var darkDelta: Int = 0
        var moonDelta: Int = 0
        var weatherDelta: Int = 0
    }

    // MARK: - Signal Weights

    private let wAmbient: Double = 0.40
    private let wPosture: Double = 0.15
    private let wDark:    Double = 0.15
    private let wMoon:    Double = 0.15
    private let wWeather: Double = 0.15

    // MARK: - Update

    func update(sensors: SensorSnapshot) {
        if sessionStartTime == nil { sessionStartTime = Date() }

        let rawAmbientSignal = 1.0 - sensors.ambientLight
        let rawPostureSignal = postureScore(pitch: sensors.devicePitch, roll: sensors.deviceRoll)
        let adaptMinutes = sensors.darkAdaptationMinutes
        let rawAdaptSignal = min(adaptMinutes / 30.0, 1.0) * 0.3

        let rawMoonSignal = sensors.moonIllumination * 0.3
        let rawWeatherSignal: Double = {
            guard let w = sensors.weather else { return 0 }
            switch w.lowercased() {
            case "thunderstorm":                        return 0.25  // danger + low viz
            case "rain", "drizzle":                     return 0.20  // wet road, low viz
            case "fog", "mist", "haze":                 return 0.15  // low visibility
            case "snow":                                return 0.0   // ground reflection compensates
            default:                                    return 0.0
            }
        }()

        // Apply toggles — inactive factors use neutral values
        let ambientSignal = ambientFactorActive ? rawAmbientSignal : 1.0
        let postureSignal = postureFactorActive ? rawPostureSignal : 1.0
        let adaptSignal   = darkAdaptationActive ? rawAdaptSignal   : 0.0
        let moonSignal    = moonFactorActive     ? rawMoonSignal    : 0.0
        let weatherSignal = weatherFactorActive  ? rawWeatherSignal : 0.0

        // Compute base brightness (5-factor model)
        let weighted = ambientSignal * wAmbient
                     + postureSignal * wPosture
                     + (1.0 - adaptSignal) * wDark
                     + (1.0 - moonSignal) * wMoon
                     + (1.0 + weatherSignal) * wWeather

        let denom = max(wAmbient + postureSignal * wPosture + wDark + wMoon + wWeather, 0.01)
        let base = weighted / denom
        if let manual = manualBrightness {
            // 手动模式：完全关闭自动机制，亮度就是手动值。
            targetBrightness = min(max(manual, 0.1), 1.0)
        } else {
            // Daylight gate: when the debounced detector reports bright daylight
            // the torch is pointless — turn it off (level 0). The gate consumes
            // the debounced isDaylight (not the raw ambient), so torch-off stays
            // in sync with the HUD notice and no single bright frame (warm-up,
            // streetlight) can kill the torch before the debounce confirms.
            targetBrightness = sensors.isDaylight ? 0 : min(max(base, 0.1), batterySaverCap)
        }

        // Proportional gap attribution
        let ambShortfall  = ambientFactorActive  ? (1.0 - ambientSignal) * wAmbient   : 0
        let posShortfall  = postureFactorActive  ? (1.0 - postureSignal) * wPosture   : 0
        let darkShortfall = darkAdaptationActive ? adaptSignal * wDark                : 0
        let moonShortfall = moonFactorActive     ? moonSignal * wMoon                 : 0
        let weathShortfall = weatherFactorActive ? (0.25 - weatherSignal) * wWeather  : 0

        let totalShortfall = ambShortfall + posShortfall + darkShortfall
                           + moonShortfall + weathShortfall
        let shares = totalShortfall > 0.0001
            ? (ambShortfall / totalShortfall, posShortfall / totalShortfall,
               darkShortfall / totalShortfall, moonShortfall / totalShortfall,
               weathShortfall / totalShortfall)
            : (0.0, 0.0, 0.0, 0.0, 0.0)

        let optAmbient  = ambientFactorActive  ? 1.0 : ambientSignal
        let optPosture  = postureFactorActive  ? 1.0 : postureSignal
        let optAdapt    = darkAdaptationActive ? 0.0 : adaptSignal
        let optMoon     = moonFactorActive     ? 0.0 : moonSignal
        let optWeather  = weatherFactorActive  ? 0.25 : weatherSignal
        let maxWeighted = optAmbient * wAmbient + optPosture * wPosture
                        + (1.0 - optAdapt) * wDark + (1.0 - optMoon) * wMoon
                        + (1.0 + optWeather) * wWeather
        let maxDenom = wAmbient + optPosture * wPosture + wDark + wMoon + wWeather
        let theoreticalMax = maxWeighted / max(maxDenom, 0.01)
        let gap = theoreticalMax - base

        func attr(_ shortfall: Double) -> Int {
            guard totalShortfall > 0.0001 else { return 0 }
            return -Int(round(shortfall / totalShortfall * gap * 100))
        }

        let ambDelta  = attr(ambShortfall)
        let posDelta  = attr(posShortfall)
        let darkDelta = attr(darkShortfall)
        let moonDelta = attr(moonShortfall)
        let weathDelta = attr(weathShortfall)

        updateFactorDetails(sensors: sensors,
                            shares: shares,
                            ambDelta: ambDelta, posDelta: posDelta,
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
                                     shares: (Double, Double, Double, Double, Double),
                                      ambDelta: Int, posDelta: Int,
                                      darkDelta: Int, moonDelta: Int, weathDelta: Int) {
        factorDetails.ambientShare = shares.0
        factorDetails.postureShare = shares.1
        factorDetails.darkShare = shares.2
        factorDetails.moonShare = shares.3
        factorDetails.weatherShare = shares.4
        factorDetails.ambientDelta = ambDelta
        factorDetails.postureDelta = posDelta
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

    /// Enter manual mode at an absolute level. Replacing the level is stable —
    /// there is no offset to double-count, and auto mechanisms stay off until
    /// `resetManualBrightness()`.
    func setManualBrightness(_ level: Double) {
        // 0 也允许：手动拖到底 = 完全关闭闪光灯。
        manualBrightness = min(max(level, 0.0), 1.0)
    }
    func resetManualBrightness() { manualBrightness = nil }

    // MARK: - Factor Toggles

    func toggleAmbientFactor()  { ambientFactorActive.toggle() }
    func togglePostureFactor()  { postureFactorActive.toggle() }
    func toggleDarkFactor()     { darkAdaptationActive.toggle() }
    func toggleMoonFactor()     { moonFactorActive.toggle() }
    func toggleWeatherFactor()  { weatherFactorActive.toggle() }

}

// MARK: - Sensor Snapshot

struct SensorSnapshot {
    let ambientLight: Double
    let devicePitch: Double
    let deviceRoll: Double
    let moonIllumination: Double
    let weather: String?
    let darkAdaptationMinutes: Double
    /// Debounced "bright daylight" from the front-camera detector — the single
    /// source of truth for the torch-off gate (the raw ambientLight is used only
    /// for the ambient brightness factor, not for the gate).
    let isDaylight: Bool
}
