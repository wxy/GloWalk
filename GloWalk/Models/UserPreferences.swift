import SwiftUI

final class UserPreferences: ObservableObject {
    @AppStorage("defaultBrightness") var defaultBrightness: Double = 0.7
    @AppStorage("enableWiFiArrival") var enableWiFiArrival: Bool = false
    @AppStorage("arrivalWiFiSSIDs") var arrivalWiFiSSIDs: String = ""
    @AppStorage("language") var language: String = "system"

    static let shared = UserPreferences()
    private init() {}
}
