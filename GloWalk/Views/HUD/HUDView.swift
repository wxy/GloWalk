import SwiftUI

struct HUDView: View {
    /// Owned by ContentView so the walk survives navigating to History.
    @ObservedObject var viewModel: HUDViewModel
    let goToHistory: () -> Void

    /// Moon phase decoration only appears at night (18:00–05:59).
    private var isNightTime: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 18 || hour < 6
    }

    /// Unified system notice bar at the top of the screen. Shows the
    /// highest-priority notice: camera denied (tap → Settings) > occlusion
    /// (torch off in pocket) > bright daylight (torch off). Reserves its height
    /// so the layout doesn't jump when a notice appears.
    private var topNoticeBar: some View {
        let active = viewModel.cameraDeniedForAmbient || viewModel.occlusionNoticeVisible || viewModel.isDaylight
        return VStack(spacing: 0) {
            if viewModel.cameraDeniedForAmbient {
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
                    .padding(.vertical, 5).padding(.horizontal, 14)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.gloAmber.opacity(0.12)))
                }
            } else if viewModel.occlusionNoticeVisible {
                // Only claim "torch off in pocket" when the torch was actually on
                // and the screen was dimmed — never when paused or in daylight.
                noticeRow(icon: "exclamationmark.triangle.fill", text: L10n.hudOccluded)
            } else if viewModel.isDaylight {
                noticeRow(icon: "sun.max.fill", text: L10n.hudDaylight)
            }
        }
        .frame(height: 30, alignment: .top)
        .padding(.top, 8)
        .animation(.easeInOut(duration: 0.25), value: active)
    }

    private func noticeRow(icon: String, text: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.gloBody(11))
            Text(text).font(.gloBody(11))
        }
        .foregroundColor(.gloGold)
        .padding(.vertical, 5).padding(.horizontal, 14)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.gloGold.opacity(0.1)))
    }

    /// Poster-style celestial backdrop: the same giant moon/sun disc peeking
    /// into the top-left corner (radius 0.8× the HUD width, only the lower-right
    /// arc visible), so the HUD matches the poster's proportions. No weather
    /// badge — the bottom factor row already shows the weather condition and
    /// the bottom bar shows the provider.
    private var celestialBackdrop: some View {
        GeometryReader { geo in
            let radius = geo.size.width * 0.8
            let center = CGPoint(x: -radius * 0.30, y: -radius * 0.22)
            Group {
                if isNightTime {
                    if let moonImg = UIImage(named: "\(viewModel.currentMoonPhaseName).jpg") {
                        Image(uiImage: moonImg)
                            .resizable()
                            .scaledToFill()
                            .frame(width: radius * 2, height: radius * 2)
                            .clipShape(Circle())
                            .opacity(0.45)
                    } else {
                        Image(systemName: "moon.fill")
                            .font(.system(size: radius * 0.55))
                            .foregroundColor(.gloGold.opacity(0.4))
                    }
                } else {
                    if let sunImg = UIImage(named: "sun.jpg") {
                        Image(uiImage: sunImg)
                            .resizable()
                            .scaledToFill()
                            .frame(width: radius * 2, height: radius * 2)
                            .clipShape(Circle())
                            .opacity(0.45)
                    } else {
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: radius * 0.55))
                            .foregroundColor(.gloGold.opacity(0.4))
                    }
                }
            }
            .position(center)
        }
        .allowsHitTesting(false)
    }

    @State private var isManual = false
    @State private var isEnding = false
    @State private var showSettings = false
    @State private var isEndingZeroStep = false
    @State private var isTorchPaused = false
    @State private var hasShownCameraAlert = false
    @State private var showCameraDeniedAlert = false

    var body: some View {
        ZStack {
            // Always pure black. In bright daylight the foreground is brightened
            // via uiBrightnessBoost, but the background stays black — a lighter
            // surface would clash with the walk-data row and wash out the icon
            // outlines, while black keeps every element in one consistent tone.
            Color.gloBlack.ignoresSafeArea()

            // Poster-style sun/moon backdrop behind everything.
            celestialBackdrop

            // Top area — camera denied warning + moon phase decoration
            VStack(spacing: 0) {
                // Walk-independent controls — very top right, not in the moon row.
                HStack {
                    Spacer()
                    Button(action: { goToHistory() }) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 16))
                            .foregroundColor(.gloGold.opacity(0.7))
                    }
                    .padding(.horizontal, 8)
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16))
                            .foregroundColor(.gloGold.opacity(0.7))
                    }
                    .padding(.trailing, 16)
                }
                .padding(.top, 12)

                // Unified system notice bar — camera denied / occlusion / daylight
                topNoticeBar
                Spacer()
            }

            VStack(spacing: 0) {
                Spacer()

                // Central glow — double-tap to end
                GlowCircleView(brightness: viewModel.brightness,
                              cadence: viewModel.cadence,
                              isPaused: viewModel.torchPaused)
                    .onTapGesture(count: 2) {
                        Haptic.heavy()
                        if viewModel.stepCount == 0 {
                            isEndingZeroStep = true
                            viewModel.isActive = false
                            viewModel.sensorManager.stop()
                            viewModel.locationManager.stopRecording()
                            viewModel.sensorTimer?.invalidate()
                            if let s = viewModel.currentWalkSession {
                                PersistenceController.shared.container.viewContext.delete(s)
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
                            // Haptic when the long press is recognized, fired via
                            // the gesture's own callback — observing @GestureState
                            // with .onChange caused "action tried to update multiple
                            // times per frame" during repeated long presses.
                            .onChanged { _ in Haptic.medium() }
                            .onEnded { _ in
                                viewModel.torchPaused.toggle()
                                Haptic.medium()
                            }
                    )
                // Constellation path — poster-sized band, fixed space (no layout jump)
                ConstellationPathView(
                    points: viewModel.pathPoints,
                    isActive: viewModel.isActive && viewModel.pathPoints.count >= 2,
                    stepCount: viewModel.stepCount
                )
                .frame(height: 170)
                .padding(.horizontal, 32)
                .opacity(viewModel.pathPoints.count >= 2 ? 0.7 : 0)

                Spacer().frame(height: 12)

                // Brightness progress lines directly above the factor row so
                // the levels and the factor deductions read as one unit.
                brightnessProgressLines

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
        .onAppear { viewModel.startWalk() }
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

    /// Two thin 10-segment progress lines: screen brightness fills left-to-right
    /// (white, ☀ at the start), torch brightness fills right-to-left (warm,
    /// 🔦 at the start). Coarse levels only — the factor row below explains the
    /// gap to 100%.
    private var brightnessProgressLines: some View {
        VStack(spacing: 2) {
            progressLine(value: viewModel.screenBrightness,
                         fillColor: .white,
                         glyph: "sun.max.fill",
                         shares: viewModel.factorShares,
                         leadingToTrailing: true)
                .frame(height: 9, alignment: .bottom)
            progressLine(value: viewModel.brightness,
                         fillColor: Color.gloTorchCore,
                         glyph: "flashlight.on.fill",
                         shares: viewModel.factorShares,
                         leadingToTrailing: false)
                .frame(height: 9, alignment: .bottom)
                .opacity(viewModel.torchPaused ? 0.35 : 1.0)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
    }

    private func progressLine(value: Double, fillColor: Color,
                              glyph: String, shares: [Double],
                              leadingToTrailing: Bool) -> some View {
        let filled = min(max(Int((value * 10).rounded()), 0), 10)
        let reversed = !leadingToTrailing
        return HStack(spacing: 2) {
            // Same-width slots on both sides (a transparent placeholder where
            // there's no glyph) so the 10 middle segments align across the two
            // progress lines.
            glyphSlot(leadingToTrailing ? glyph : nil, color: fillColor)
            ForEach(0..<10, id: \.self) { i in
                let lit = reversed ? i >= 10 - filled : i < filled
                Capsule()
                    .fill(segmentColor(index: i, filled: filled,
                                       fillColor: fillColor, shares: shares,
                                       reversed: reversed))
                    .frame(maxWidth: .infinity)
                    .frame(height: 4)
                    // Per-segment glow so the brightness bars read as the lit
                    // "level" elements and stand apart from the factor row.
                    // Three stacked shadows (tight core + wide bloom) so the
                    // glow survives the dim screen brightness the app applies
                    // at night.
                    .shadow(color: lit ? fillColor.opacity(1.0) : .clear,
                            radius: lit ? 3 : 0)
                    .shadow(color: lit ? fillColor.opacity(0.8) : .clear,
                            radius: lit ? 8 : 0)
                    .shadow(color: lit ? fillColor.opacity(0.45) : .clear,
                            radius: lit ? 15 : 0)
            }
            glyphSlot(leadingToTrailing ? nil : glyph, color: fillColor)
        }
        .animation(.easeOut(duration: 0.25), value: filled)
    }

    private func glyphSlot(_ systemName: String?, color: Color) -> some View {
        Group {
            if let systemName {
                Image(systemName: systemName)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(color.opacity(0.9))
            } else {
                Color.clear
            }
        }
        .frame(width: 10)
    }

    /// Filled segments use the level color; the remaining segments are colored
    /// by whichever factor dominates their span of the deduction space (same
    /// semantics as the ring design), falling back to a dim placeholder.
    private func segmentColor(index: Int, filled: Int, fillColor: Color,
                              shares: [Double], reversed: Bool) -> Color {
        if reversed ? index >= 10 - filled : index < filled {
            return fillColor
        }
        return deductionColor(segmentIndex: index, filled: filled,
                              shares: shares, reversed: reversed)
            ?? Color.white.opacity(0.12)
    }

    private func deductionColor(segmentIndex i: Int, filled: Int,
                                shares: [Double], reversed: Bool) -> Color? {
        let total = shares.reduce(0, +)
        guard total > 0.0001, filled < 10 else { return nil }
        let dedCount = Double(10 - filled)
        // Deductions grow outward from the filled edge, in factor-share order.
        let pos: Double
        if reversed {
            pos = Double(9 - filled - i)   // right edge is the filled side
        } else {
            pos = Double(i - filled)       // left edge is the filled side
        }
        let segStart = pos / dedCount
        let segEnd = (pos + 1) / dedCount
        var acc = 0.0
        var bestIndex: Int?
        var bestOverlap = 0.0
        for (j, share) in shares.enumerated() {
            let span = share / total
            let overlap = max(0, min(segEnd, acc + span) - max(segStart, acc))
            if overlap > bestOverlap {
                bestOverlap = overlap
                bestIndex = j
            }
            acc += span
        }
        return bestIndex.map { Color.gloFactorPalette[$0] }
    }

    /// 5-factor row weighted by influence: ambient 40%, rest 15% each
    private var topStatusRow: some View {
        GeometryReader { geo in
            // Reserve the 4 inter-factor gaps (4 × 3pt) so the factors fill the
            // row exactly — otherwise the content overflows by 12pt and the
            // right margin collapses (left looks wider).
            let slot = geo.size.width - 12
            HStack(spacing: 3) {
                factorCol(FactorCell(icon: "eye.fill", label: ambientLabel,
                                      delta: ambDelta, active: ambActive, id: "ambient"))
                    .frame(width: slot * 0.40)
                factorCol(FactorCell(icon: "iphone", label: L10n.factorPosture,
                                      delta: posDelta, active: posActive, id: "posture"))
                    .frame(width: slot * 0.15)
                factorCol(FactorCell(icon: "moon.zzz.fill", label: L10n.factorDark,
                                      delta: darkDelta, active: darkActive, id: "dark"))
                    .frame(width: slot * 0.15)
                factorCol(FactorCell(icon: "moon.fill", label: moonLabel,
                                      delta: moonDelta, active: moonActive, id: "moon"))
                    .frame(width: slot * 0.15)
                factorCol(FactorCell(icon: "cloud.fill", label: weatherLabel,
                                      delta: weatherDelta, active: weatherActive, id: "weather"))
                    .frame(width: slot * 0.15)
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
                    // Color dot matches the factor's ring-segment color, so the
                    // deduction segments on the glow rings are traceable back to
                    // this row.
                    Circle()
                        .fill(factorColor(cell.id))
                        .frame(width: 4, height: 4)
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

    private func factorColor(_ id: String) -> Color {
        switch id {
        case "posture": return Color.gloFactorPosture
        case "dark":    return Color.gloFactorDark
        case "moon":    return Color.gloFactorMoon
        case "weather": return Color.gloFactorWeather
        default:        return Color.gloFactorAmbient
        }
    }

    // Convenience accessors for factor card data
    /// Ambient factor label — the descriptor is gated on the debounced daylight
    /// state, so "明亮/Bright" only appears once the torch actually turns off
    /// (below that, the raw reading maps to fairly-bright / dim / dark). Without
    /// camera permission there is no reading, so the descriptor is omitted.
    private var ambientLabel: String {
        guard !viewModel.cameraDeniedForAmbient else { return L10n.factorAmbient }
        return "\(L10n.factorAmbient) · \(L10n.ambientBrightnessLabel(viewModel.sensorManager.ambientLightLevel, isDaylight: viewModel.isDaylight))"
    }

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
        // Six fixed-width cells at 16% each (96% total) with a 2% margin on each
        // side. Fixed widths (not .frame(maxWidth: .infinity)) can't expand and
        // overflow, so the row settles on first render; long text scales down.
        GeometryReader { geo in
            // Five stats at 16% each + the weather cell at 20% (the remaining 4%)
            // so longer provider names like "Open-Meteo" fit without shrinking.
            let cell = geo.size.width * 0.16
            let weatherCell = geo.size.width * 0.20
            HStack(spacing: 0) {
                // Uniform cell height so the GPS icon and the weather placeholder
                // line up with the plain-text cells. Emoji is followed by a space
                // so the icon and value have a small consistent gap.
                Text("🦶 \(viewModel.stepCount)\(L10n.hudUnitSteps)")
                    .frame(width: cell, height: 16, alignment: .center)
                Text("📏 \(viewModel.elapsedDistance)")
                    .frame(width: cell, height: 16, alignment: .center)
                Text("⏱ \(viewModel.elapsedMinutes)\(L10n.hudUnitMinutes)")
                    .frame(width: cell, height: 16, alignment: .center)
                Text(viewModel.estimatedMinutesRemaining < 0
                     ? "🔋 ∞"
                     : "🔋 \(viewModel.estimatedMinutesRemaining)\(L10n.hudUnitMinutes)")
                    .frame(width: cell, height: 16, alignment: .center)
                gpsIndicator
                    .frame(width: cell, height: 16, alignment: .center)
                weatherServiceLabel
                    .frame(width: weatherCell, height: 16, alignment: .center)
            }
            .font(.gloMono(10))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundColor(.gloGold.opacity(min(0.55 * viewModel.uiBrightnessBoost, 1.0)))
        }
        .frame(height: 38)
        .padding(.horizontal, 8)
        .padding(.bottom, 2)
        .padding(.top, 6)
        .background(Color.black.opacity(0.6))
    }

    /// GPS signal-quality indicator: arrow rotates with the compass heading;
    /// its color reflects fix accuracy (green good / yellow marginal / red weak
    /// or no fix), with an optional ±m readout.
    private var gpsIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: viewModel.gpsActive ? "location.north.line.fill" : "location.slash")
                .font(.system(size: 10))  // match the row's 10pt text height
                .foregroundColor(viewModel.gpsQualityColor)
                .rotationEffect(.degrees(viewModel.gpsActive ? viewModel.currentHeading : 0))
            if let acc = viewModel.gpsAccuracyLabel {
                Text(acc)
                    .foregroundColor(viewModel.gpsQualityColor.opacity(0.8))
            }
        }
    }

    // MARK: - Weather Provider Label

    /// Shows only the weather provider actually in use, rightmost in the bottom
    /// bar.  Weather links to Apple's legal attribution page; Open-Meteo links
    /// to their homepage. Nothing is shown when no weather data is available
    /// (flexible, not a reserved slot — reserving width caused layout issues).
    @ViewBuilder
    private var weatherServiceLabel: some View {
        switch viewModel.weatherCard.provider {
        case .apple:
            Button(action: {
                if let url = URL(string: "https://weatherkit.apple.com/legal-attribution.html") {
                    UIApplication.shared.open(url)
                }
            }) {
                // No font override — inherits the bottom bar's uniform size.
                Text("\u{F8FF} Weather")
                    .foregroundColor(.gloGold.opacity(min(0.6 * viewModel.uiBrightnessBoost, 1.0)))
            }
        case .openMeteo:
            Button(action: {
                if let url = URL(string: "https://open-meteo.com/") {
                    UIApplication.shared.open(url)
                }
            }) {
                Text("Open-Meteo")
                    .foregroundColor(.gloGold.opacity(min(0.6 * viewModel.uiBrightnessBoost, 1.0)))
            }
        case .none:
            // Placeholder keeps the cell at text height (Color.clear would expand
            // and make the cell tall) and signals weather is still loading.
            Text("···")
                .foregroundColor(.gloGold.opacity(min(0.25 * viewModel.uiBrightnessBoost, 0.5)))
        }
    }
}
