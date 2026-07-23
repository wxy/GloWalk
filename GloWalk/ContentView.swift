import SwiftUI
import AVFoundation

enum AppScreen {
    case privacy, cameraPermission, splash, hud, history
}

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("language") private var language: String = "system"
    @StateObject private var appState = AppState()
    @State private var screen: AppScreen = .privacy
    @State private var hudID = UUID()

    /// The effective locale derived from user's language preference,
    /// injected into the view hierarchy so all Text(LocalizedStringKey) resolves correctly.
    private var resolvedLocale: Locale {
        switch language {
        case "en": return Locale(identifier: "en")
        case "zh-Hans": return Locale(identifier: "zh-Hans")
        default: return .autoupdatingCurrent
        }
    }

    var body: some View {
        Group {
            switch screen {
            case .privacy:
                PrivacyConsentView()
            case .cameraPermission:
                CameraPermissionView { _ in
                    screen = .splash
                }
            case .splash:
                SplashView(isQuickLaunch: appState.isQuickLaunch) {
                    screen = .hud
                }
            case .hud:
                HUDView(goToHistory: { screen = .history; hudID = UUID() })
                    .environmentObject(appState)
                    .id(hudID)
            case .history:
                HistoryListView(goToSplash: { screen = .splash })
            }
        }
        .environment(\.locale, resolvedLocale)
        .onAppear {
            if hasCompletedOnboarding {
                let status = AVCaptureDevice.authorizationStatus(for: .video)
                screen = (status == .notDetermined) ? .cameraPermission : .splash
            }
        }
        .onChange(of: hasCompletedOnboarding) { done in
            if done {
                let status = AVCaptureDevice.authorizationStatus(for: .video)
                screen = (status == .notDetermined) ? .cameraPermission : .splash
            }
        }
        .onChange(of: language) { newLang in
            // Sync to AppleLanguages so Bundle + String Catalog resolve correctly
            if newLang == "system" {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.set([newLang], forKey: "AppleLanguages")
            }
        }
    }
}

class AppState: ObservableObject {
    @Published var isQuickLaunch = false
}

// MARK: - Camera Permission

struct CameraPermissionView: View {
    let onDecision: (Bool) -> Void

    var body: some View {
        ZStack {
            Color.gloBlack.ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "camera.fill")
                    .font(.gloBody(48)).foregroundColor(.gloAmber)
                Text(L10n.cameraTitle)
                    .font(.gloHeadline(22)).foregroundColor(.white)
                Text(L10n.cameraDescription)
                    .font(.gloBody(14)).foregroundColor(.white.opacity(0.7)).multilineTextAlignment(.center)
                HStack(spacing: 24) {
                    Button(L10n.cameraDeny) { onDecision(false) }.foregroundColor(.white.opacity(0.5))
                    Button(L10n.cameraAllow) {
                        Task {
                            _ = await AVCaptureDevice.requestAccess(for: .video)
                            await MainActor.run { onDecision(true) }
                        }
                    }
                    .foregroundColor(.gloAmber).font(.gloHeadline(17))
                }
            }.padding(32)
        }
    }
}
