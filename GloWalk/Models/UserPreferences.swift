import SwiftUI

final class UserPreferences: ObservableObject {
    @AppStorage("defaultBrightness") var defaultBrightness: Double = 0.7
    @AppStorage("enableWiFiArrival") var enableWiFiArrival: Bool = false
    @AppStorage("arrivalWiFiSSIDs") var arrivalWiFiSSIDs: String = ""

    static let shared = UserPreferences()
    private init() {}
}
