import SwiftUI

struct HUDView: View {
    @StateObject private var viewModel = HUDViewModel()
    @EnvironmentObject var appState: AppState
    @AppStorage("language") private var appLanguage: String = "system"
    let goToHistory: () -> Void
    @State private var isManual = false
    @State private var isEnding = false
    @State private var showSettings = false
    @State private var isEndingZeroStep = false

    /// Effective language considering user preference + system fallback
    private var isZh: Bool {
        if appLanguage == "en" { return false }
        if appLanguage == "zh-Hans" { return true }
        return Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
    }

    var body: some View {
        ZStack {
            Color.gloBlack.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top status row — leave room for notch/Dynamic Island
                topStatusRow
                    .padding(.top, 48)

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
                            isEndingZeroStep = true
                            viewModel.sensorManager.stop()
                            viewModel.locationManager.stopRecording()
                            viewModel.sensorTimer?.invalidate()
                            // Mark as abandoned rather than deleting — @FetchRequest may
                            // have already seen the object; marking ensures filter works
                            if let s = viewModel.currentWalkSession {
                                s.endType = "abandoned"
                                s.endTime = Date()
                                PersistenceController.shared.save()
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

                // Constellation path — fixed space, no layout jump
                ConstellationPathView(
                    points: viewModel.pathPoints,
                    heading: viewModel.currentHeading,
                    isActive: viewModel.isActive && viewModel.pathPoints.count >= 2
                )
                .frame(height: 100)
                .padding(.horizontal, 32)
                .opacity(viewModel.pathPoints.count >= 2 ? 0.7 : 0)

                Spacer()

                // Occlusion warning — fixed height to prevent layout shift
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.gloBody(11))
                    Text(L10n.hudOccluded).font(.gloBody(11))
                }
                .foregroundColor(.gloGold)
                .padding(.vertical, 4).padding(.horizontal, 12)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.gloGold.opacity(0.1)))
                .padding(.bottom, 4)
                .opacity(viewModel.isTorchOccluded ? 1 : 0)

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

    /// 3×2 grid: left (moon) | center (GPS) | right (weather)
    /// Side columns share remaining width equally; center is narrow (icons only).
    private var topStatusRow: some View {
        VStack(spacing: 2) {
            // Row 1 — moon card · GPS · weather card
            HStack(alignment: .center, spacing: 4) {
                MoonCardView(data: viewModel.moonCard) { viewModel.toggleMoonFactor() }
                    .frame(maxWidth: .infinity, alignment: .leading)
                gpsIndicator
                    .frame(width: 36)
                WeatherCardView(data: viewModel.weatherCard) { viewModel.toggleWeatherFactor() }
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: 24)

            // Row 2 — lunar date · place name · gregorian date
            HStack(alignment: .center, spacing: 4) {
                Text(viewModel.lunarDateStr)
                    .font(.gloBody(9)).foregroundColor(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Group {
                    if viewModel.placeName.isEmpty {
                        Text(viewModel.gpsActive ? L10n.hudGPS : L10n.hudGPSUnavailable)
                    } else {
                        Text(verbatim: viewModel.placeName)
                    }
                }
                .font(.gloBody(9)).foregroundColor(.white.opacity(0.45))
                .lineLimit(1)
                .frame(width: 70)
                Text(viewModel.gregorianDateStr)
                    .font(.gloBody(9)).foregroundColor(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: 14)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    private var gpsIndicator: some View {
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

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 0) {
            Text(isZh ? "🦶\(viewModel.stepCount)步" : "🦶\(viewModel.stepCount) steps")
            Text(" · \(viewModel.elapsedDistance)")
            Text(isZh ? " · ⏱\(viewModel.elapsedMinutes)分钟" : " · ⏱\(viewModel.elapsedMinutes)min")
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
        .foregroundColor(.gloGold.opacity(0.55 * viewModel.uiBrightnessBoost))
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
        .padding(.top, 6)
        .background(Color.black.opacity(0.6))
    }
}
