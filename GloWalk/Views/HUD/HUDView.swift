import SwiftUI

struct HUDView: View {
    @StateObject private var viewModel = HUDViewModel()
    @EnvironmentObject var appState: AppState
    let goToHistory: () -> Void

    /// Moon phase decoration only appears at night (18:00–05:59).
    private var isNightTime: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 18 || hour < 6
    }
    @State private var isManual = false
    @State private var isEnding = false
    @State private var showSettings = false
    @State private var isEndingZeroStep = false

    var body: some View {
        ZStack {
            Color.gloBlack.ignoresSafeArea()

            // Moon phase image — top-left corner, below status row
            VStack {
                HStack {
                    if isNightTime,
                   let moonImg = UIImage(named: "\(viewModel.currentMoonPhaseName).jpg") {
                        Image(uiImage: moonImg)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                            .opacity(0.45)
                            .padding(.leading, 12)
                            .padding(.top, 48)
                    }
                    Spacer()
                }
                Spacer()
            }

            VStack(spacing: 0) {
                Spacer()

                // Central glow — double-tap to end
                GlowCircleView(brightness: viewModel.brightness, isManual: isManual,
                              cadence: viewModel.cadence)
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
                // Constellation path — fixed space, no layout jump
                ConstellationPathView(
                    points: viewModel.pathPoints,
                    isActive: viewModel.isActive && viewModel.pathPoints.count >= 2
                )
                .frame(height: 100)
                .padding(.horizontal, 32)
                .opacity(viewModel.pathPoints.count >= 2 ? 0.7 : 0)

                Spacer().frame(height: 12)

                // Occlusion warning — above the status row, not between cards and bar
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.gloBody(11))
                    Text(L10n.hudOccluded).font(.gloBody(11))
                }
                .foregroundColor(.gloGold)
                .padding(.vertical, 4).padding(.horizontal, 12)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.gloGold.opacity(0.1)))
                .padding(.bottom, 2)
                .opacity(viewModel.isTorchOccluded ? 1 : 0)

                // Status row + bottom bar — tight grouping
                topStatusRow

                // Thin divider
                Rectangle()
                    .fill(Color.gloGold.opacity(0.10))
                    .frame(height: 0.5)
                    .padding(.horizontal, 24)
                    .padding(.top, 4)

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

    // MARK: - Status Row

    /// 3×2 factor grid: all 6 factors toggleable, left-aligned
    private var topStatusRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                FactorCardView(icon: "eye.fill", label: L10n.isZh ? "环境光" : "Ambient",
                               brightnessDelta: viewModel.factorCards.first(where: {$0.id=="ambient"})?.brightnessDelta ?? 0,
                               isActive: viewModel.factorCards.first(where: {$0.id=="ambient"})?.isActive ?? true) {
                    viewModel.toggleFactor(id: "ambient")
                }
                FactorCardView(icon: "iphone", label: L10n.isZh ? "姿态" : "Posture",
                               brightnessDelta: viewModel.factorCards.first(where: {$0.id=="posture"})?.brightnessDelta ?? 0,
                               isActive: viewModel.factorCards.first(where: {$0.id=="posture"})?.isActive ?? true) {
                    viewModel.toggleFactor(id: "posture")
                }
                FactorCardView(icon: "sun.max.fill", label: L10n.isZh ? "屏幕" : "Screen",
                               brightnessDelta: viewModel.factorCards.first(where: {$0.id=="screen"})?.brightnessDelta ?? 0,
                               isActive: viewModel.factorCards.first(where: {$0.id=="screen"})?.isActive ?? true) {
                    viewModel.toggleFactor(id: "screen")
                }
            }
            HStack(spacing: 4) {
                FactorCardView(icon: "moon.zzz.fill", label: L10n.isZh ? "暗适应" : "Adapt",
                               brightnessDelta: viewModel.factorCards.first(where: {$0.id=="dark"})?.brightnessDelta ?? 0,
                               isActive: viewModel.factorCards.first(where: {$0.id=="dark"})?.isActive ?? true) {
                    viewModel.toggleFactor(id: "dark")
                }
                MoonCardView(data: viewModel.moonCard) { viewModel.toggleMoonFactor() }
                WeatherCardView(data: viewModel.weatherCard) { viewModel.toggleWeatherFactor() }
            }
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 0) {
            Text(L10n.isZh ? "🦶\(viewModel.stepCount)步" : "🦶\(viewModel.stepCount) steps")
            Text(" · \(viewModel.elapsedDistance)")
            Text(L10n.isZh ? " · ⏱\(viewModel.elapsedMinutes)分钟" : " · ⏱\(viewModel.elapsedMinutes)min")
            Spacer()
            if viewModel.estimatedMinutesRemaining < 0 {
                Text("🔋∞")
            } else {
                Text("🔋\(viewModel.estimatedMinutesRemaining)min")
            }
            Spacer()
            Image(systemName: viewModel.gpsActive ? "location.fill" : "location.slash")
                .font(.system(size: 10))
                .foregroundColor(viewModel.gpsActive ? .green.opacity(0.6) : .red.opacity(0.35))
                .padding(.trailing, 6)
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
