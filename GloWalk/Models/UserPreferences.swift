import SwiftUI

final class UserPreferences: ObservableObject {
    @AppStorage("language") var language: String = "system"
    @AppStorage("healthSyncEnabled") var healthSyncEnabled: Bool = true

    static let shared = UserPreferences()
    private init() {}
}
