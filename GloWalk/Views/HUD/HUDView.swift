import SwiftUI

struct HUDView: View {
    @StateObject private var viewModel = HUDViewModel()
    @EnvironmentObject var appState: AppState
    @State private var showEndConfirm = false
    @State private var confirmOpacity: Double = 0
    @State private var countdown: Int = 5

    var body: some View {
        ZStack {
            Color.gloBlack.ignoresSafeArea()

            // Small moon phase in top-left
            MoonCornerView()

            VStack(spacing: 0) {
                Spacer()

                // Central glow — tap to end
                GlowCircleView(brightness: viewModel.brightness)
                    .gesture(
                        DragGesture(minimumDistance: 10)
                            .onChanged { v in
                                let delta = -v.translation.height / 200.0
                                let new = min(max(viewModel.brightness + delta, 0.1), 1.0)
                                if abs(new - viewModel.brightness) > 0.05 {
                                    Haptic.selection()
                                }
                                viewModel.setManualBrightness(new)
                            }
                    )
                    .onTapGesture {
                        countdown = 5
                        withAnimation(.easeIn(duration: 0.2)) { confirmOpacity = 1; showEndConfirm = true }
                        // Countdown timer
                        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { t in
                            countdown -= 1
                            if countdown <= 0 {
                                t.invalidate()
                                withAnimation(.easeOut(duration: 0.4)) { confirmOpacity = 0 }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showEndConfirm = false }
                            }
                        }
                    }
                    .overlay(alignment: .bottom) {
                        PulsingHint(text: "轻点熄灭")
                            .offset(y: 28)
                    }

                // Constellation path
                if viewModel.pathPoints.count >= 2 {
                    ConstellationPathView(
                        points: viewModel.pathPoints,
                        heading: viewModel.currentHeading,
                        isActive: viewModel.isActive
                    )
                    .frame(height: 100)
                    .padding(.horizontal, 32)
                }

                Spacer()

                // Occlusion warning
                if viewModel.isTorchOccluded {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.gloBody(11))
                        Text("闪光灯被遮挡，已自动关闭").font(.gloBody(11))
                    }
                    .foregroundColor(.gloGold)
                    .padding(.vertical, 4).padding(.horizontal, 12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.gloGold.opacity(0.1)))
                    .padding(.bottom, 4)
                }

                // Bottom info bar — compact integrated row
                bottomInfoBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
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
        // Custom end confirmation
        .overlay {
            if showEndConfirm {
                endConfirmOverlay
            }
        }
        .fullScreenCover(isPresented: $viewModel.showArrivalSummary) {
            ArrivalSummaryView(viewModel: viewModel)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
    }

    // MARK: - Bottom Info Bar

    private var bottomInfoBar: some View {
        VStack(spacing: 6) {
            // Moon / Weather cards
            HStack(spacing: 8) {
                if let moon = viewModel.moonCard {
                    MoonCardView(data: moon) { viewModel.toggleMoonFactor() }
                }
                if let weather = viewModel.weatherCard {
                    WeatherCardView(data: weather) { viewModel.toggleWeatherFactor() }
                }
                // GPS status
                Circle()
                    .fill(viewModel.gpsActive ? Color.green.opacity(0.6) : Color.red.opacity(0.3))
                    .frame(width: 5, height: 5)
                Text("GPS")
                    .font(.gloBody(10))
                    .foregroundColor(.white.opacity(0.35))
                Spacer()
            }

            // Battery bar
            Rectangle()
                .fill(Color.gloGold.opacity(0.3))
                .frame(height: 2)
                .padding(.trailing, 8)

            // Stats row
            HStack(spacing: 0) {
                Text("🦶\(viewModel.stepCount)步")
                Text(" · \(viewModel.elapsedDistance)")
                Text(" · ⏱\(viewModel.elapsedMinutes)min")
                Spacer()
                if viewModel.estimatedMinutesRemaining < 0 {
                    Text("🔋∞")
                } else {
                    Text("🔋\(viewModel.estimatedMinutesRemaining)min")
                }
            }
            .font(.gloMono(11))
            .foregroundColor(.gloGold.opacity(0.55))
        }
    }

    // MARK: - End Confirmation Overlay

    private func dismissConfirm() {
        countdown = 0
        withAnimation(.easeOut(duration: 0.3)) { confirmOpacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showEndConfirm = false }
    }

    private var endConfirmOverlay: some View {
        ZStack {
            Color.black.opacity(0.5 * confirmOpacity).ignoresSafeArea()
                .onTapGesture { dismissConfirm() }

            VStack(spacing: 24) {
                Text("🏮")
                    .font(.system(size: 36))

                Text("确认熄灯")
                    .font(.gloHeadline(22))
                    .foregroundColor(.gloGold)

                Text("结束本次步行\n自动生成夜路足迹海报")
                    .font(.gloBody(14))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)

                Text("\(countdown) 秒后自动取消")
                    .font(.gloBody(12))
                    .foregroundColor(.white.opacity(0.25))

                Button(action: {
                    Haptic.heavy()
                    dismissConfirm()
                    viewModel.endWalkAndNotify()
                }) {
                    Text("确认熄灯")
                        .font(.gloHeadline(16))
                        .foregroundColor(.black)
                        .frame(width: 180, height: 48)
                        .background(Color.gloGold)
                        .cornerRadius(24)
                }
                .padding(.top, 4)
            }
            .padding(36)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(white: 0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color.gloGold.opacity(0.15), lineWidth: 0.5)
                    )
            )
            .opacity(confirmOpacity)
        }
    }
}
