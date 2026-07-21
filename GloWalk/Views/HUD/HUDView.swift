import SwiftUI

struct HUDView: View {
    @StateObject private var viewModel = HUDViewModel()
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            Color.gloBlack.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Central glow
                GlowCircleView(brightness: viewModel.brightness)
                    .gesture(
                        DragGesture(minimumDistance: 10)
                            .onChanged { v in
                                let delta = -v.translation.height / 200.0
                                let new = min(max(viewModel.brightness + delta, 0.1), 1.0)
                                viewModel.setManualBrightness(new)
                            }
                    )
                    .onTapGesture(count: 2) {
                        viewModel.endWalkAndNotify()
                    }

                Spacer()

                // Info cards
                VStack(spacing: 8) {
                    if let moon = viewModel.moonCard {
                        MoonCardView(data: moon) { viewModel.toggleMoonFactor() }
                    }
                    if let weather = viewModel.weatherCard {
                        WeatherCardView(data: weather) { viewModel.toggleWeatherFactor() }
                    }
                }
                .padding(.bottom, 4)

                // Occlusion warning
                if viewModel.isTorchOccluded {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                        Text("闪光灯被遮挡，已自动关闭")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.gloAmber)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gloAmber.opacity(0.1))
                    )
                    .padding(.bottom, 4)
                }

                // Battery bar
                Rectangle()
                    .fill(Color.gloAmber.opacity(0.3))
                    .frame(width: UIScreen.main.bounds.width * 0.4, height: 2)
                    .padding(.bottom, 8)

                // Bottom bar
                HStack {
                    Text("🦶\(viewModel.stepCount)步 \(viewModel.elapsedDistance) ⏱\(viewModel.elapsedMinutes)min")
                        .font(.system(size: 12, design: .monospaced))
                    Spacer()
                    Text("🔋\(viewModel.estimatedMinutesRemaining)min")
                        .font(.system(size: 12, design: .monospaced))
                }
                .foregroundColor(.gloAmber.opacity(0.6))
                .padding(.horizontal, 24)
                .padding(.bottom, 8)

                // End button
                Button(action: { viewModel.endWalkAndNotify() }) {
                    Text("结束并通知")
                        .font(.system(size: 14))
                        .foregroundColor(.gloAmber)
                        .padding(.horizontal, 24).padding(.vertical, 8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.gloAmber.opacity(0.4), lineWidth: 1)
                        )
                }
                .padding(.bottom, 8)

                // Navigation row
                HStack(spacing: 32) {
                    NavigationLink(destination: EmptyView()) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 14))
                            .foregroundColor(.gloAmber.opacity(0.4))
                    }
                    NavigationLink(destination: EmptyView()) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14))
                            .foregroundColor(.gloAmber.opacity(0.4))
                    }
                }
                .padding(.bottom, 32)
            }
        }
        .gloWalkHUD()
        .onAppear { viewModel.startWalk(isQuickLaunch: appState.isQuickLaunch) }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            viewModel.willResignActive()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            viewModel.didBecomeActive()
        }
    }
}
