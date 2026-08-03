import SwiftUI
import AVFoundation
import CoreLocation

enum AppScreen {
    case privacy, cameraPermission, locationPermission, splash, hud, history
}

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("language") private var language: String = "system"
    @StateObject private var appState = AppState()
    @State private var screen: AppScreen = .privacy
    @State private var hudID = UUID()
    /// Owned here (not by HUDView) so the walk survives navigating to History —
    /// peeking at history keeps the flashlight on and the walk recording, and a
    /// "Resume Walk" entry returns to the same session. Replaced on a new walk.
    @State private var hudViewModel = HUDViewModel()
    @Environment(\.scenePhase) private var scenePhase

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
                    checkLocationThenProceed()
                }
            case .locationPermission:
                LocationPermissionView { _ in
                    screen = .splash
                }
            case .splash:
                SplashView(isQuickLaunch: appState.isQuickLaunch) {
                    screen = .hud
                }
            case .hud:
                HUDView(viewModel: hudViewModel, goToHistory: { screen = .history })
                    .environmentObject(appState)
                    .id(hudID)
            case .history:
                HistoryListView(
                    hasActiveWalk: hudViewModel.isActive,
                    onResume: { screen = .hud },
                    onNewWalk: {
                        // Defensive: end any still-active walk before discarding it.
                        if hudViewModel.isActive { hudViewModel.endWalkAbruptly() }
                        hudViewModel = HUDViewModel()
                        hudID = UUID()
                        screen = .splash
                    }
                )
            }
        }
        .environment(\.locale, resolvedLocale)
        .onAppear {
            if hasCompletedOnboarding {
                checkPermissionsThenProceed()
            }
        }
        .onChange(of: hasCompletedOnboarding) { done in
            if done {
                checkPermissionsThenProceed()
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
        .onChange(of: scenePhase) { phase in
            // Re-check permissions when returning from Settings, so if the user
            // granted a previously-denied permission, we pick it up.
            if phase == .active, hasCompletedOnboarding,
               screen != .hud, screen != .history {
                checkPermissionsThenProceed()
            }
        }
    }

    // MARK: - Permission Flow

    private func checkPermissionsThenProceed() {
        let camStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if camStatus == .notDetermined {
            screen = .cameraPermission
            return
        }
        checkLocationThenProceed()
    }

    private func checkLocationThenProceed() {
        let locStatus = CLLocationManager().authorizationStatus
        if locStatus == .notDetermined {
            screen = .locationPermission
        } else {
            screen = .splash
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
                Button(L10n.cameraContinue) {
                    Task {
                        _ = await AVCaptureDevice.requestAccess(for: .video)
                        await MainActor.run { onDecision(true) }
                    }
                }
                .foregroundColor(.gloAmber).font(.gloHeadline(17))
                .padding(.horizontal, 40).padding(.vertical, 12)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gloAmber.opacity(0.4), lineWidth: 1))
            }.padding(32)
        }
    }
}

// MARK: - Location Permission

/// Thin delegate wrapper that retains the CLLocationManager while the
/// system permission dialog is visible, then calls the completion block.
private final class LocationPermissionRequester: NSObject, CLLocationManagerDelegate {
    let manager = CLLocationManager()
    private let onComplete: () -> Void

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        super.init()
        manager.delegate = self
    }

    func request() {
        manager.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onComplete()
    }
}

struct LocationPermissionView: View {
    let onDecision: (Bool) -> Void
    @State private var requester: LocationPermissionRequester?

    var body: some View {
        ZStack {
            Color.gloBlack.ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "location.fill")
                    .font(.gloBody(48)).foregroundColor(.gloAmber)
                Text(L10n.locationTitle)
                    .font(.gloHeadline(22)).foregroundColor(.white)
                Text(L10n.locationDescription)
                    .font(.gloBody(14)).foregroundColor(.white.opacity(0.7)).multilineTextAlignment(.center)
                Button(L10n.locationContinue) {
                    let r = LocationPermissionRequester {
                        DispatchQueue.main.async {
                            requester = nil
                            onDecision(true)
                        }
                    }
                    requester = r
                    r.request()
                }
                .foregroundColor(.gloAmber).font(.gloHeadline(17))
                .padding(.horizontal, 40).padding(.vertical, 12)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gloAmber.opacity(0.4), lineWidth: 1))
            }.padding(32)
        }
    }
}
