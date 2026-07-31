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
    @State private var isTorchPaused = false
    @State private var hasShownCameraAlert = false
    @State private var showCameraDeniedAlert = false
    @GestureState private var isLongPressing = false

    var body: some View {
        ZStack {
            Color.gloBlack.ignoresSafeArea()

            // Top area — camera denied warning + moon phase decoration
            VStack(spacing: 0) {
                // Camera denied warning — top banner
                Button(action: {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "camera.fill").font(.gloBody(11))
                        Text(L10n.hudCameraDenied).font(.gloBody(11))
                        Image(systemName: "chevron.right").font(.gloBody(9))
                    }
                    .foregroundColor(.gloAmber)
                    .padding(.vertical, 6).padding(.horizontal, 14)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.gloAmber.opacity(0.12)))
                }
                .padding(.top, 48)
                .opacity(viewModel.cameraDeniedForAmbient ? 1 : 0)

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
                            .padding(.top, 8)
                    }
                    Spacer()
                }
                Spacer()
            }

            VStack(spacing: 0) {
                Spacer()

                // Central glow — double-tap to end
                GlowCircleView(brightness: viewModel.brightness, isManual: isManual,
                              cadence: viewModel.cadence,
                              isPaused: viewModel.torchPaused)
                    .onTapGesture(count: 2) {
                        Haptic.heavy()
                        if viewModel.stepCount == 0 {
                            isEndingZeroStep = true
                            viewModel.sensorManager.stop()
                            viewModel.locationManager.stopRecording()
                            viewModel.sensorTimer?.invalidate()
                            if let s = viewModel.currentWalkSession {
                                s.endType = "abandoned"
                                s.endTime = Date()
                                PersistenceController.shared.save()
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                goToHistory()
                            }
                        } else {
                            isEnding = true
                            viewModel.endWalkAndNotify()
                        }
                    }
                    .onTapGesture(count: 1) {
                        if isManual {
                            isManual = false
                            viewModel.resetToAutoBrightness()
                            Haptic.light()
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 10)
                            .onChanged { v in
                                let delta = -v.translation.height / 200.0
                                let new = min(max(viewModel.brightness + delta, 0.1), 1.0)
                                if abs(new - viewModel.brightness) > 0.05 { Haptic.selection() }
                                if !isManual { isManual = true; Haptic.light() }
                                viewModel.setManualBrightness(new)
                            }
                            .onEnded { _ in Haptic.selection() }
                    )
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.8)
                            .updating($isLongPressing) { value, state, _ in state = value }
                            .onEnded { _ in
                                viewModel.torchPaused.toggle()
                                Haptic.medium()
                            }
                    )
                    .onChange(of: isLongPressing) { pressing in
                        if pressing { Haptic.medium() }
                    }
                // Constellation path — poster-sized band, fixed space (no layout jump)
                ConstellationPathView(
                    points: viewModel.pathPoints,
                    isActive: viewModel.isActive && viewModel.pathPoints.count >= 2
                )
                .frame(height: 140)
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

                // Service attribution
                attributionStrip
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
                        Text(isEndingZeroStep ? L10n.hudZeroStep : L10n.hudDrawing)
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
        .onChange(of: viewModel.cameraDeniedForAmbient) { denied in
            if denied && !hasShownCameraAlert {
                hasShownCameraAlert = true
                showCameraDeniedAlert = true
            }
        }
        .alert(L10n.hudCameraDeniedTitle, isPresented: $showCameraDeniedAlert) {
            Button(L10n.hudCameraDeniedSettings) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button(L10n.hudCameraDeniedDismiss, role: .cancel) {}
        } message: {
            Text(L10n.hudCameraDeniedMessage)
        }
    }

    // MARK: - Status Row

    /// 5-factor row weighted by influence: ambient 40%, rest 15% each
    private var topStatusRow: some View {
        GeometryReader { geo in
            let total = geo.size.width
            HStack(spacing: 3) {
                factorCol(FactorCell(icon: "eye.fill", label: L10n.isZh ? "环境光" : "Ambient",
                                      delta: ambDelta, active: ambActive, id: "ambient"))
                    .frame(width: total * 0.40)
                factorCol(FactorCell(icon: "iphone", label: L10n.isZh ? "姿态" : "Posture",
                                      delta: posDelta, active: posActive, id: "posture"))
                    .frame(width: total * 0.15)
                factorCol(FactorCell(icon: "moon.zzz.fill", label: L10n.isZh ? "暗适应" : "Adapt",
                                      delta: darkDelta, active: darkActive, id: "dark"))
                    .frame(width: total * 0.15)
                factorCol(FactorCell(icon: "moon.fill", label: moonLabel,
                                      delta: moonDelta, active: moonActive, id: "moon"))
                    .frame(width: total * 0.15)
                factorCol(FactorCell(icon: "cloud.fill", label: weatherLabel,
                                      delta: weatherDelta, active: weatherActive, id: "weather"))
                    .frame(width: total * 0.15)
            }
        }
        .frame(height: 38)
        .padding(.horizontal, 12)
    }

    private func factorCol(_ cell: FactorCell) -> some View {
        let boost = viewModel.uiBrightnessBoost
        return Button(action: { viewModel.toggleFactor(id: cell.id) }) {
            VStack(spacing: 1) {
                Text(cell.label)
                    .font(.gloBody(9))
                    .lineLimit(1)
                    .foregroundColor(cell.active ? .white : .white.opacity(min(0.3 * boost, 0.7)))
                HStack(spacing: 2) {
                    Image(systemName: cell.icon)
                        .font(.system(size: 8))
                    Text(cell.delta > 0 ? "+\(cell.delta)%" : "\(cell.delta)%")
                        .font(.gloMono(10))
                }
                .foregroundColor(cell.delta != 0 ? .gloAmber : .white.opacity(min(0.25 * boost, 0.6)))
            }
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(cell.active ? Color.gloAmber.opacity(min(0.08 * boost, 0.20)) : Color.white.opacity(min(0.02 * boost, 0.06)))
            )
        }
        .buttonStyle(.plain)
        .opacity(min(cell.active ? 0.85 : 0.4 * boost, 1.0))
    }

    private struct FactorCell {
        let icon: String; let label: String; let delta: Int
        let active: Bool; let id: String
    }

    // Convenience accessors for factor card data
    private var ambDelta: Int { factorDelta("ambient") }
    private var posDelta: Int { factorDelta("posture") }
    private var darkDelta: Int { factorDelta("dark") }
    private var ambActive: Bool { factorActive("ambient") }
    private var posActive: Bool { factorActive("posture") }
    private var darkActive: Bool { factorActive("dark") }
    private var moonDelta: Int { viewModel.moonCard.brightnessDelta }
    private var moonActive: Bool { viewModel.moonCard.isActive }
    private var moonLabel: String { viewModel.moonCard.phaseName }
    private var weatherDelta: Int { viewModel.weatherCard.brightnessDelta }
    private var weatherActive: Bool { viewModel.weatherCard.isActive }
    private var weatherLabel: String { viewModel.weatherCard.condition }

    private func factorDelta(_ id: String) -> Int {
        viewModel.factorCards.first(where: { $0.id == id })?.brightnessDelta ?? 0
    }
    private func factorActive(_ id: String) -> Bool {
        viewModel.factorCards.first(where: { $0.id == id })?.isActive ?? true
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 0) {
            Text(L10n.isZh ? "🦶\(viewModel.stepCount)步" : "🦶\(viewModel.stepCount) steps")
            Text(" · \(viewModel.elapsedDistance)")
            Text(L10n.isZh ? " · ⏱\(viewModel.elapsedMinutes)分钟" : " · ⏱\(viewModel.elapsedMinutes)min")
            Spacer()
            if viewModel.estimatedMinutesRemaining < 0 {
                Text(L10n.isZh ? "🔋∞" : "🔋∞")
            } else {
                Text(L10n.isZh ? "🔋\(viewModel.estimatedMinutesRemaining)分钟" : "🔋\(viewModel.estimatedMinutesRemaining)min")
            }
            Spacer()
            Image(systemName: viewModel.gpsActive ? "location.north.line.fill" : "location.slash")
                .font(.system(size: 12))
                .foregroundColor(viewModel.gpsActive ? .green.opacity(0.6) : .red.opacity(0.35))
                .rotationEffect(.degrees(viewModel.gpsActive ? viewModel.currentHeading : 0))
            Button(action: { goToHistory() }) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 14))
                    .foregroundColor(.gloGold.opacity(0.5))
            }
            .padding(.horizontal, 10)
            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .foregroundColor(.gloGold.opacity(0.6))
            }
        }
        .font(.gloMono(11))
        .foregroundColor(.gloGold.opacity(0.55 * viewModel.uiBrightnessBoost))
        .padding(.horizontal, 20)
        .padding(.bottom, 2)
        .padding(.top, 6)
        .background(Color.black.opacity(0.6))
    }

    // MARK: - Attribution Strip

    /// Weather data source acknowledgment — always visible at the very bottom.
    ///  Weather links to Apple's legal attribution page;
    /// Open-Meteo links to their homepage.
    private var attributionStrip: some View {
        HStack(spacing: 4) {
            Spacer()
            Button(action: {
                if let url = URL(string: "https://weatherkit.apple.com/legal-attribution.html") {
                    UIApplication.shared.open(url)
                }
            }) {
                Text("\u{F8FF} Weather")
                    .font(.gloBody(8))
                    .foregroundColor(.gloGold.opacity(0.35 * viewModel.uiBrightnessBoost))
            }
            Text("·")
                .font(.gloBody(8))
                .foregroundColor(.gloGold.opacity(0.25 * viewModel.uiBrightnessBoost))
            Button(action: {
                if let url = URL(string: "https://open-meteo.com/") {
                    UIApplication.shared.open(url)
                }
            }) {
                Text("Open-Meteo")
                    .font(.gloBody(8))
                    .foregroundColor(.gloGold.opacity(0.35 * viewModel.uiBrightnessBoost))
            }
            Spacer()
        }
        .padding(.bottom, 10)
        .padding(.top, 2)
    }
}
