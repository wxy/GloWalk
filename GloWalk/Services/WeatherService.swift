import CoreLocation
#if canImport(WeatherKit)
import WeatherKit
#endif

/// Hybrid weather: tries Apple WeatherKit first, falls back to free Open-Meteo.
/// WeatherKit is more accurate globally but restricted in mainland China;
/// Open-Meteo works everywhere with no API key.
///
/// When WeatherKit is the active provider, the UI must display the
/// " Weather" trademark and link to the legal attribution page
/// (https://weatherkit.apple.com/legal-attribution.html).
@MainActor
final class WeatherService: ObservableObject {
    enum Provider { case apple, openMeteo, none }

    @Published var currentCondition: String?
    @Published var provider: Provider = .none

    /// Consecutive WeatherKit failures before we stop retrying it for the rest
    /// of the walk. WeatherKit JWT generation is done internally by the
    /// framework from the app's entitlement and can fail persistently on some
    /// devices/regions (a known Apple-side issue — not a code or entitlement
    /// problem). Once it fails twice in a walk we skip it and go straight to
    /// Open-Meteo to avoid repeated token-generation attempts and log noise.
    private var weatherKitFailures = 0
    private let weatherKitMaxFailures = 2

    func fetch(at location: CLLocation) async {
        // Try Apple WeatherKit first (richer data, restricted in China)
        if #available(iOS 16, *) {
            if weatherKitFailures >= weatherKitMaxFailures {
                Log.debug("[Weather] WeatherKit skipped — \(weatherKitFailures) consecutive failures this walk, using Open-Meteo")
            } else if let condition = await tryWeatherKit(at: location) {
                currentCondition = condition
                provider = .apple
                weatherKitFailures = 0
                Log.debug("[Weather] Apple WeatherKit success: \(condition)")
                return
            } else {
                weatherKitFailures += 1
            }
        }
        // Fall back to Open-Meteo (free, works globally including China)
        if let condition = await tryOpenMeteo(at: location) {
            currentCondition = condition
            provider = .openMeteo
            Log.debug("[Weather] Open-Meteo success: \(condition)")
        } else {
            provider = .none
            Log.error("[Weather] No weather available — WeatherKit and Open-Meteo both failed")
        }
    }

    // MARK: - Apple WeatherKit (iOS 16+)

    @available(iOS 16, *)
    private func tryWeatherKit(at location: CLLocation) async -> String? {
        do {
            let weather = try await WeatherKit.WeatherService.shared.weather(for: location)
            return normalize(weather.currentWeather.condition)
        } catch {
            Log.error("[Weather] WeatherKit failed, falling back to Open-Meteo: \(error.localizedDescription)")
            return nil
        }
    }

    @available(iOS 16, *)
    private func normalize(_ condition: WeatherCondition) -> String {
        switch condition {
        case .clear, .mostlyClear, .hot: return "clear"
        case .cloudy, .mostlyCloudy, .partlyCloudy: return "cloud"
        case .foggy, .haze, .smoky: return "fog"
        case .drizzle, .freezingDrizzle: return "drizzle"
        case .rain, .heavyRain, .sunShowers, .freezingRain: return "rain"
        case .snow, .heavySnow, .flurries, .blizzard, .blowingSnow,
             .sleet, .wintryMix, .hail: return "snow"
        case .thunderstorms, .isolatedThunderstorms, .scatteredThunderstorms,
             .strongStorms, .tropicalStorm, .hurricane: return "thunderstorm"
        default: return "cloud"
        }
    }

    // MARK: - Open-Meteo (works worldwide, no API key)

    private func tryOpenMeteo(at location: CLLocation) async -> String? {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        guard let url = URL(string:
            "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current_weather=true") else {
            return nil
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            return mapWeatherCode(decoded.current_weather.weathercode)
        } catch {
            Log.error("[Weather] Open-Meteo also failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func mapWeatherCode(_ code: Int) -> String? {
        switch code {
        case 0:        return "clear"
        case 1,2,3:    return "cloud"
        case 45,48:    return "fog"
        case 51,53,55,56,57: return "drizzle"
        case 61,63,65,66,67: return "rain"
        case 71,73,75,77:    return "snow"
        case 80,81,82: return "rain"
        case 85,86:    return "snow"
        case 95,96,99: return "thunderstorm"
        default:       return nil
        }
    }
}

private struct OpenMeteoResponse: Codable {
    let current_weather: CurrentWeather
}
private struct CurrentWeather: Codable {
    let weathercode: Int
}
