import Foundation

enum NightMemoryTheme: String, Equatable {
    case rain
    case resumed
    case changingLight
    case winding
    case longWalk
    case moonlit
    case quiet

    var taglineKey: String {
        switch self {
        case .rain: return "tagline.rain"
        case .resumed: return "tagline.resumed"
        case .changingLight: return "tagline.streetlight"
        case .winding: return "tagline.winding"
        case .longWalk: return "tagline.adaptation"
        case .moonlit: return "tagline.moon"
        case .quiet: return "tagline.quiet"
        }
    }
}

/// A location-free description of what the completed walk felt like.
/// Coordinates are used only to measure turns and are never retained here.
struct NightMemoryProfile: Equatable {
    struct Sample {
        let latitude: Double
        let longitude: Double
        let torchBrightness: Double
        let segmentID: Int64
    }

    let theme: NightMemoryTheme
    let segmentCount: Int
    let lightRange: Double
    let significantTurns: Int

    init(duration: TimeInterval, distance: Double, moonPhase: String,
         weatherCondition: String?, samples: [Sample]) {
        segmentCount = Set(samples.map(\.segmentID)).count
        lightRange = Self.robustRange(samples.map(\.torchBrightness))
        significantTurns = Self.turnCount(samples)

        let weather = weatherCondition?.lowercased() ?? ""
        if ["rain", "drizzle", "thunderstorm"].contains(weather) {
            theme = .rain
        } else if segmentCount > 1 {
            theme = .resumed
        } else if lightRange >= 0.35 {
            theme = .changingLight
        } else if significantTurns >= 2 {
            theme = .winding
        } else if duration >= 20 * 60 || distance >= 1_500 {
            theme = .longWalk
        } else if ["full_moon", "waxing_gibbous", "waning_gibbous"].contains(moonPhase) {
            theme = .moonlit
        } else {
            theme = .quiet
        }
    }

    /// Use the 10th–90th percentile span so a single camera/torch spike cannot
    /// decide the memory for an otherwise steady walk.
    private static func robustRange(_ values: [Double]) -> Double {
        guard values.count >= 2 else { return 0 }
        let sorted = values.sorted()
        let low = sorted[Int(Double(sorted.count - 1) * 0.10)]
        let high = sorted[Int(Double(sorted.count - 1) * 0.90)]
        return max(0, high - low)
    }

    /// Count deliberate-looking direction changes inside each recording
    /// segment. Tiny GPS moves are ignored, and paused segments never connect.
    private static func turnCount(_ samples: [Sample]) -> Int {
        let grouped = Dictionary(grouping: samples, by: \.segmentID)
        return grouped.values.reduce(0) { total, segment in
            guard segment.count >= 3 else { return total }
            let latitude = segment.map(\.latitude).reduce(0, +) / Double(segment.count)
            let lonScale = max(cos(latitude * .pi / 180), 0.01)
            var vectors: [(Double, Double)] = []
            for (a, b) in zip(segment, segment.dropFirst()) {
                let dx = (b.longitude - a.longitude) * lonScale
                let dy = b.latitude - a.latitude
                guard hypot(dx, dy) > 0.000005 else { continue }
                vectors.append((dx, dy))
            }
            let turns = zip(vectors, vectors.dropFirst()).filter { before, after in
                let cross = before.0 * after.1 - before.1 * after.0
                let dot = before.0 * after.0 + before.1 * after.1
                return abs(atan2(cross, dot)) >= 35 * .pi / 180
            }.count
            return total + turns
        }
    }
}
