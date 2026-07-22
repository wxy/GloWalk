import SwiftUI

struct HUDView: View {
    @StateObject private var viewModel = HUDViewModel()
    @EnvironmentObject var appState: AppState
    let goToHistory: () -> Void
    @State private var isManual = false
    @State private var isEnding = false
    @State private var showSettings = false
    @State private var isEndingZeroStep = false

    var body: some View {
        ZStack {
            Color.gloBlack.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top status row
                topStatusRow
                    .padding(.top, 8)

                Spacer()

                // Central glow — double-tap to end
                GlowCircleView(brightness: viewModel.brightness, isManual: isManual)
                    .gesture(
                        DragGesture(minimumDistance: 10)
                            .onChanged { v in
                                let delta = -v.translation.height / 200.0
                                let new = min(max(viewModel.brightness + delta, 0.1), 1.0)
                                if abs(new - viewModel.brightness) > 0.05 { Haptic.selection() }
                                isManual = true
                                viewModel.setManualBrightness(new)
                            }
                    )
                    .onTapGesture(count: 2) {
                        Haptic.heavy()
                        if viewModel.stepCount == 0 {
                            // Show brief loading, then navigate
                            isEndingZeroStep = true
                            viewModel.sensorManager.stop()
                            viewModel.locationManager.stopRecording()
                            viewModel.sensorTimer?.invalidate()
                            if let s = viewModel.currentWalkSession {
                                PersistenceController.shared.container.viewContext.delete(s)
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                goToHistory()
                            }
                        } else {
                            isEnding = true
                            viewModel.endWalkAndNotify()
                        }
                    }
                    .onTapGesture(count: 1) {
                        // Single tap on brightness number → back to auto
                        if isManual {
                            isManual = false
                            viewModel.resetToAutoBrightness()
                        }
                    }
                    .overlay(alignment: .bottom) {
                        Text(L10n.hudDoubleTapToEnd)
                            .font(.gloHeadline(11))
                            .foregroundColor(.gloGold.opacity(0.4))
                            .offset(y: 28)
                    }

                // Constellation path — always reserve space
                ConstellationPathView(
                    points: viewModel.pathPoints,
                    heading: viewModel.currentHeading,
                    isActive: viewModel.isActive && viewModel.pathPoints.count >= 2
                )
                .frame(height: 100)
                .padding(.horizontal, 32)

                Spacer()

                // Occlusion warning
                if viewModel.isTorchOccluded {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.gloBody(11))
                        Text(L10n.hudOccluded).font(.gloBody(11))
                    }
                    .foregroundColor(.gloGold)
                    .padding(.vertical, 4).padding(.horizontal, 12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.gloGold.opacity(0.1)))
                    .padding(.bottom, 4)
                }

                // Bottom bar — flush with screen bottom
                bottomBar
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
        // Loading overlay when ending walk
        .overlay {
            if (isEnding || isEndingZeroStep) && !viewModel.showArrivalSummary {
                ZStack {
                    Color.black.opacity(0.6).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView().tint(.gloGold).scaleEffect(1.5)
                        Text(isEndingZeroStep ? L10n.hudEnding : L10n.hudDrawing)
                            .font(.gloBody(14)).foregroundColor(.gloGold.opacity(0.7))
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .fullScreenCover(isPresented: $viewModel.showArrivalSummary) {
            ArrivalSummaryView(viewModel: viewModel, onComplete: goToHistory)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
    }

    // MARK: - Top Status Row

    private var topStatusRow: some View {
        VStack(spacing: 2) {
            // Row 1: Moon | GPS icon | Weather
            HStack(alignment: .center, spacing: 0) {
                cellLeft {
                    if let moon = viewModel.moonCard {
                        MoonCardView(data: moon) { viewModel.toggleMoonFactor() }
                    } else { Spacer().frame(height: 22) }
                }
                cellCenter {
                    HStack(spacing: 3) {
                        Image(systemName: viewModel.gpsActive ? "location.fill" : "location.slash")
                            .font(.system(size: 10))
                            .foregroundColor(viewModel.gpsActive ? .green.opacity(0.7) : .red.opacity(0.4))
                        if viewModel.gpsActive {
                            Image(systemName: "location.north.line.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.gloGold.opacity(0.5))
                                .rotationEffect(.degrees(viewModel.currentHeading))
                        }
                    }
                }
                cellRight {
                    if let weather = viewModel.weatherCard {
                        WeatherCardView(data: weather) { viewModel.toggleWeatherFactor() }
                    } else { Spacer().frame(height: 22) }
                }
            }
            // Row 2: Lunar date | City | Gregorian date
            HStack(alignment: .center, spacing: 0) {
                cellLeft {
                    Text(viewModel.lunarDateStr)
                        .font(.gloBody(9)).foregroundColor(.white.opacity(0.5))
                }
                cellCenter {
                    Text(verbatim: viewModel.placeName.isEmpty
                         ? (viewModel.gpsActive ? "GPS" : "GPS 不可用")
                         : viewModel.placeName)
                        .font(.gloBody(9)).foregroundColor(.white.opacity(0.45))
                        .lineLimit(1)
                }
                cellRight {
                    Text(viewModel.gregorianDateStr)
                        .font(.gloBody(9)).foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    private func cellLeft<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content().frame(maxWidth: .infinity, alignment: .leading)
    }
    private func cellCenter<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content().frame(maxWidth: .infinity, alignment: .center)
    }
    private func cellRight<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content().frame(maxWidth: .infinity, alignment: .trailing)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        let zh = Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
        return HStack(spacing: 0) {
            Text(zh ? "🦶\(viewModel.stepCount)步" : "🦶\(viewModel.stepCount) steps")
            Text(" · \(viewModel.elapsedDistance)")
            Text(zh ? " · ⏱\(viewModel.elapsedMinutes)分钟" : " · ⏱\(viewModel.elapsedMinutes)min")
            Spacer()
            if viewModel.estimatedMinutesRemaining < 0 {
                Text("🔋∞")
            } else {
                Text("🔋\(viewModel.estimatedMinutesRemaining)min")
            }
            Spacer()
            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .foregroundColor(.gloGold.opacity(0.3))
            }
        }
        .font(.gloMono(11))
        .foregroundColor(.gloGold.opacity(0.55))
        .padding(.horizontal, 20)
        .padding(.bottom, 2)
        .padding(.top, 6)
        .background(Color.gloBlack)
    }
}
