import SwiftUI

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @StateObject private var appState = AppState()
    @State private var showSplash = true
    @State private var showCameraPrompt = false
    @State private var cameraDone = false

    var body: some View {
        Group {
            if !hasCompletedOnboarding {
                PrivacyConsentView()
            } else if showCameraPrompt && !cameraDone {
                CameraPermissionView { allowed in
                    cameraDone = true
                    showCameraPrompt = false
                }
            } else if showSplash {
                SplashView(isQuickLaunch: appState.isQuickLaunch) {
                    showSplash = false
                }
            } else {
                HUDView().environmentObject(appState)
            }
        }
        .onAppear {
            if hasCompletedOnboarding {
                let status = AVCaptureDevice.authorizationStatus(for: .video)
                if status == .notDetermined {
                    showCameraPrompt = true
                } else {
                    cameraDone = true
                }
            }
        }
    }
}

class AppState: ObservableObject {
    @Published var isWalkActive = false
    @Published var isQuickLaunch = false
}

// MARK: - Camera Permission Explanation

struct CameraPermissionView: View {
    let onDecision: (Bool) -> Void

    var body: some View {
        ZStack {
            Color.gloBlack.ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 48)).foregroundColor(.gloAmber)
                Text("环境光感知")
                    .font(.title2).foregroundColor(.white)
                Text("GloWalk 用后摄像头感知环境明暗变化\n\n不拍照、不录像、不存储任何画面\n每 5 秒采样一次即丢弃\n\n拒绝后需手动调节亮度")
                    .font(.system(size: 14)).foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                HStack(spacing: 24) {
                    Button("拒绝") { onDecision(false) }
                        .foregroundColor(.white.opacity(0.5))
                    Button("允许") {
                        Task {
                            _ = await AVCaptureDevice.requestAccess(for: .video)
                            await MainActor.run { onDecision(true) }
                        }
                    }
                    .foregroundColor(.gloAmber).fontWeight(.bold)
                }
            }.padding(32)
        }
    }
}
