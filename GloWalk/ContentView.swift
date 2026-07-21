import SwiftUI

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @StateObject private var appState = AppState()

    var body: some View {
        Group {
            if !hasCompletedOnboarding {
                PrivacyConsentView()
            } else {
                HUDView()
                    .environmentObject(appState)
            }
        }
    }
}

class AppState: ObservableObject {
    @Published var isWalkActive = false
    @Published var isQuickLaunch = false
}
