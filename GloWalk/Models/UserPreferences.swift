import SwiftUI

final class UserPreferences: ObservableObject {
    @AppStorage("language") var language: String = "system"

    static let shared = UserPreferences()
    private init() {}
}
