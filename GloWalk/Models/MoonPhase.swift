import Foundation

enum MoonPhase {
    struct MoonData {
        let phase: String
        let illumination: Double // 0.0 (new) to 1.0 (full)
    }

    /// Calculate moon phase for a given date using a simplified astronomical algorithm.
    /// Based on the synodic month (29.53 days). Reference: known new moon Jan 6, 2000 18:14 UTC.
    static func current(date: Date = Date()) -> MoonData {
        let knownNewMoon = Date(timeIntervalSince1970: 947192040)
        let synodicMonth: Double = 29.53058867 * 24 * 3600

        let elapsed = date.timeIntervalSince(knownNewMoon)
        let age = elapsed.truncatingRemainder(dividingBy: synodicMonth)
        let normalizedAge = (age < 0 ? age + synodicMonth : age) / synodicMonth
        let illumination = (1.0 - cos(normalizedAge * 2 * .pi)) / 2.0

        let phase: String
        switch normalizedAge {
        case 0..<0.0625, 0.9375..<1.0: phase = "new_moon"
        case 0.0625..<0.1875:          phase = "waxing_crescent"
        case 0.1875..<0.3125:          phase = "first_quarter"
        case 0.3125..<0.4375:          phase = "waxing_gibbous"
        case 0.4375..<0.5625:          phase = "full_moon"
        case 0.5625..<0.6875:          phase = "waning_gibbous"
        case 0.6875..<0.8125:          phase = "last_quarter"
        case 0.8125..<0.9375:          phase = "waning_crescent"
        default:                        phase = "unknown"
        }

        return MoonData(phase: phase, illumination: illumination)
    }

    /// Returns brightness factor: 1.0 = full brightness needed, ~0.7 = full moon
    static func brightnessFactor(illumination: Double) -> Double {
        1.0 - (illumination * 0.3)
    }
}
