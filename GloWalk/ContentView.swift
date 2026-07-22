import SwiftUI
import AVFoundation

enum AppScreen {
    case privacy, cameraPermission, splash, hud, history
}

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @StateObject private var appState = AppState()
    @State private var screen: AppScreen = .privacy
    @State private var hudID = UUID()

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
                Text("环境光感知")
                    .font(.gloHeadline(22)).foregroundColor(.white)
                Text("GloWalk 用后摄像头感知环境明暗变化\n\n不拍照、不录像、不存储任何画面\n每 5 秒采样一次即丢弃\n\n拒绝后需手动调节亮度")
                    .font(.gloBody(14)).foregroundColor(.white.opacity(0.7)).multilineTextAlignment(.center)
                HStack(spacing: 24) {
                    Button("拒绝") { onDecision(false) }.foregroundColor(.white.opacity(0.5))
                    Button("允许") {
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
