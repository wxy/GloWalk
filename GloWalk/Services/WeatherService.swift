import CoreLocation
#if canImport(WeatherKit)
import WeatherKit
#endif

/// Hybrid weather: tries Apple WeatherKit first, falls back to free Open-Meteo.
/// Automatically handles mainland China and other restricted regions.
@MainActor
final class WeatherService: ObservableObject {
    enum Provider { case apple, openMeteo, none }

    @Published var currentCondition: String?
    @Published var provider: Provider = .none
    @Published var isAvailable: Bool = true

    func fetch(at location: CLLocation) async {
        // Try Apple WeatherKit first (richer data, but restricted in China)
        if #available(iOS 16, *) {
            if let condition = await tryWeatherKit(at: location) {
                currentCondition = condition
                provider = .apple
                return
            }
        }
        // Fall back to Open-Meteo (free, works globally including China)
        if let condition = await tryOpenMeteo(at: location) {
            currentCondition = condition
            provider = .openMeteo
        } else {
            provider = .none
        }
    }

    // MARK: - Apple WeatherKit (iOS 16+)

    @available(iOS 16, *)
    private func tryWeatherKit(at location: CLLocation) async -> String? {
        do {
            let weather = try await WeatherKit.WeatherService.shared.weather(for: location)
            return weather.currentWeather.condition.rawValue
        } catch {
            print("[Weather] WeatherKit failed, falling back to Open-Meteo: \(error.localizedDescription)")
            return nil
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
            print("[Weather] Open-Meteo also failed: \(error.localizedDescription)")
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
