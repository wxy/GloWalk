import CoreLocation
#if canImport(WeatherKit)
import WeatherKit
#endif

@MainActor
final class WeatherService: ObservableObject {
    @Published var currentCondition: String?
    @Published var isAvailable: Bool = false

    init() {
        if #available(iOS 16, *) {
            isAvailable = true
        }
    }

    func fetch(at location: CLLocation) async {
        guard #available(iOS 16, *), isAvailable else { return }

        let weather = WeatherKitProxy()
        if let condition = await weather.currentCondition(for: location) {
            currentCondition = condition
        }
    }
}

// MARK: - WeatherKit Proxy (avoids linking WeatherKit on iOS 15)

@available(iOS 16, *)
private struct WeatherKitProxy {
    func currentCondition(for location: CLLocation) async -> String? {
        do {
            let weather = try await WeatherKit.WeatherService.shared.weather(for: location)
            return weather.currentWeather.condition.rawValue
        } catch {
            print("Weather fetch error: \(error.localizedDescription)")
            return nil
        }
    }
}
