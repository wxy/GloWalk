import SwiftUI

/// 手动亮度拖动的纯逻辑：拖动位置从屏幕顶部（10 格 = 全亮）线性映射到
/// 下方亮度进度条位置（0 格 = 关闭闪光灯），一格一档。
enum BrightnessDrag {
    static func segment(brightness: Double) -> Int {
        min(max(Int((brightness * 10).rounded()), 0), 10)
    }

    static func level(segment: Int) -> Double {
        Double(min(max(segment, 0), 10)) / 10
    }

    /// 手指全局 y → 档位（0–10），超出范围钳制。
    static func segment(forY y: CGFloat, topY: CGFloat, bottomY: CGFloat) -> Int {
        let span = max(bottomY - topY, 1)
        let t = min(max((bottomY - y) / span, 0), 1)
        return Int((t * 10).rounded())
    }

    /// 图标偏移量 → 档位（0–10），超出范围钳制。
    static func segment(forOffset offset: CGFloat,
                        topOffset: CGFloat, bottomOffset: CGFloat) -> Int {
        let span = max(bottomOffset - topOffset, 1)
        let t = min(max((bottomOffset - offset) / span, 0), 1)
        return Int((t * 10).rounded())
    }

    /// 档位对应的图标停靠位置（顶部=全亮，底部=关闭）。
    static func slotY(segment: Int, topY: CGFloat, bottomY: CGFloat) -> CGFloat {
        let s = min(max(segment, 0), 10)
        return topY + (CGFloat(10 - s) / 10.0) * (bottomY - topY)
    }
}

/// 中央图标槽位（静止位置）的全局 frame。
private struct GlowSlotFrameKey: PreferenceKey {
    static var defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        if let next = nextValue() { value = next }
    }
}

/// 右上角控制按钮行的全局下缘 y（拖动上界）。
private struct TopControlsMaxYKey: PreferenceKey {
    static var defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        if let next = nextValue() { value = next }
    }
}

/// 下方亮度进度条的全局 y（拖动区间下界，拖到这里 = 关闭闪光灯）。
private struct BarsMinYKey: PreferenceKey {
    static var defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        if let next = nextValue() { value = next }
    }
}

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
    /// 拖动时中心图标的垂直跟随偏移；松手后停留在所选亮度档位。
    @State private var dragOffset: CGFloat = 0
    /// 当前是否正在拖动（用于在开始瞬间锚定图标的起始中心）。
    @State private var isDragging = false
    /// 本次拖动开始时图标中心的全局 y。
    @State private var dragStartCenterY: CGFloat = 0
    /// 中央图标槽位（静止位置）的全局 frame。
    @State private var glowSlotFrame: CGRect?
    /// 右上角控制按钮行的全局下缘 y（拖动上界）。
    @State private var topControlsMaxY: CGFloat?
    /// 下方亮度进度条位置的全局 y（拖到这里 = 关闭闪光灯）。
    @State private var barsY: CGFloat?
    /// 图标半径的一半（90pt 图标 → 45pt），把"边缘不越界"换算成"中心限制"。
    private let iconHalfHeight: CGFloat = 45
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
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: TopControlsMaxYKey.self,
                                               value: geo.frame(in: .global).maxY)
                    }
                )

                // Unified system notice bar — camera denied / occlusion / daylight
                topNoticeBar
                Spacer()
            }

            VStack(spacing: 0) {
                Spacer()

                // Central glow — double-tap to end；槽位静止，内容随拖动移动。
                centralGlow
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
        .onPreferenceChange(GlowSlotFrameKey.self) { glowSlotFrame = $0 }
        .onPreferenceChange(TopControlsMaxYKey.self) { topControlsMaxY = $0 }
        .onPreferenceChange(BarsMinYKey.self) { barsY = $0 }
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

    /// 中央光晕：拖动调亮度（位置映射，松手停留），单击恢复自动，双击结束步行。
    private var centralGlow: some View {
        ZStack {
            GlowCircleView(brightness: viewModel.brightness,
                          cadence: viewModel.cadence,
                          isPaused: viewModel.lightEngine.isManual && viewModel.brightness <= 0.001)
                .offset(y: dragOffset)
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
                        // 恢复自动时图标回中。
                        withAnimation(.easeOut(duration: 0.2)) { dragOffset = 0 }
                        Haptic.light()
                    }
                }
        }
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { v in
                    let slotFrame = glowSlotFrame
                        ?? CGRect(x: 0, y: UIScreen.main.bounds.midY - 120,
                                  width: 240, height: 240)
                    let glowCenter = slotFrame.midY
                    let topBound = (topControlsMaxY ?? slotFrame.minY) + iconHalfHeight
                    let bottomBound = (barsY ?? UIScreen.main.bounds.height * 0.82) - iconHalfHeight
                    if !isDragging {
                        isDragging = true
                        dragStartCenterY = glowCenter + dragOffset
                        if !isManual { isManual = true; Haptic.light() }
                    }
                    // 手指全局 y = 拖动起点图标中心 + 手指位移
                    // （手势绑定在静止槽位上，坐标不会随图标移动而漂移）。
                    let fingerY = dragStartCenterY + v.translation.height
                    // 图标先跟随手指，再按 [按钮行下缘, 亮度条] 钳制：
                    // 上界 = 右上角按钮下缘 + 半图标，下界 = 亮度条 − 半图标。
                    dragOffset = min(max(fingerY - glowCenter,
                                         topBound - glowCenter),
                                     bottomBound - glowCenter)
                    // 亮度由图标当前位置决定，保证图标位置与亮度始终一致。
                    let segment = BrightnessDrag.segment(forOffset: dragOffset,
                                                         topOffset: topBound - glowCenter,
                                                         bottomOffset: bottomBound - glowCenter)
                    let newLevel = BrightnessDrag.level(segment: segment)
                    if abs(newLevel - viewModel.brightness) > 0.001 {
                        viewModel.setManualBrightness(newLevel)
                        Haptic.selection()
                    }
                }
                .onEnded { _ in
                    isDragging = false
                    let slotFrame = glowSlotFrame
                        ?? CGRect(x: 0, y: UIScreen.main.bounds.midY - 120,
                                  width: 240, height: 240)
                    let glowCenter = slotFrame.midY
                    let topBound = (topControlsMaxY ?? slotFrame.minY) + iconHalfHeight
                    let bottomBound = (barsY ?? UIScreen.main.bounds.height * 0.82) - iconHalfHeight
                    let segment = BrightnessDrag.segment(brightness: viewModel.brightness)
                    let slot = BrightnessDrag.slotY(segment: segment,
                                                    topY: topBound, bottomY: bottomBound)
                    // 松手停在所选档位，不再回弹。
                    withAnimation(.easeOut(duration: 0.12)) {
                        dragOffset = slot - glowCenter
                    }
                    Haptic.selection()
                }
        )
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: GlowSlotFrameKey.self,
                                       value: geo.frame(in: .global))
            }
        )
    }

    /// Two thin 10-segment progress lines: screen brightness fills left-to-right
    /// (white, ☀ at the start), torch brightness fills right-to-left (warm,
    /// 🔦 at the start). Coarse levels only — the factor row below explains the
    /// gap to 100%.
    private var brightnessProgressLines: some View {
        let manual = viewModel.lightEngine.isManual
        return VStack(spacing: 2) {
            // 屏幕亮度由环境光独立控制，手动模式不影响它，因此保持正常显示。
            progressLine(value: viewModel.screenBrightness,
                         fillColor: .white,
                         glyph: "sun.max.fill",
                         shares: viewModel.factorShares,
                         leadingToTrailing: true,
                         manual: false)
                .frame(height: 9, alignment: .bottom)
            // 手电亮度在手动模式下锁定为手动值，灰色标识手动状态。
            progressLine(value: viewModel.brightness,
                         fillColor: Color.gloTorchCore,
                         glyph: "flashlight.on.fill",
                         shares: viewModel.factorShares,
                         leadingToTrailing: false,
                         manual: manual)
                .frame(height: 9, alignment: .bottom)
                .opacity(viewModel.torchPaused ? 0.35 : 1.0)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: BarsMinYKey.self,
                                       value: geo.frame(in: .global).minY)
            }
        )
    }

    private func progressLine(value: Double, fillColor: Color,
                              glyph: String, shares: [Double],
                              leadingToTrailing: Bool, manual: Bool) -> some View {
        let filled = min(max(Int((value * 10).rounded()), 0), 10)
        let reversed = !leadingToTrailing
        // Flowing "water" on the bar: a sine wave of brightness travels along
        // the lit segments (screen → right, torch → left) so the bar reads as a
        // living level. Deliberately no shadows — the flow comes from the
        // traveling brightness crest, keeping GPU cost low.
        return TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate * 3.0
            HStack(spacing: 2) {
                // Same-width slots on both sides (a transparent placeholder
                // where there's no glyph) so the 10 middle segments align
                // across the two progress lines.
                glyphSlot(leadingToTrailing ? glyph : nil, color: fillColor)
                ForEach(0..<10, id: \.self) { i in
                    let lit = reversed ? i >= 10 - filled : i < filled
                    let position = reversed ? Double(9 - i) : Double(i)
                    let wave = 0.5 + 0.5 * sin(phase - position * 0.9)
                    let glow = lit ? wave : 0.0
                    Capsule()
                        .fill(segmentColor(index: i, filled: filled,
                                           fillColor: fillColor, shares: shares,
                                           reversed: reversed, manual: manual))
                        .frame(maxWidth: .infinity)
                        .frame(height: 2)
                        // The crest travels along the bar with clear contrast,
                        // so the flow reads without any glow/bloom.
                        .opacity(lit ? 0.55 + 0.45 * glow : 1.0)
                }
                glyphSlot(leadingToTrailing ? nil : glyph, color: fillColor)
            }
            .animation(.easeOut(duration: 0.25), value: filled)
        }
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
                              shares: [Double], reversed: Bool, manual: Bool) -> Color {
        if reversed ? index >= 10 - filled : index < filled {
            // 手动模式：填充段统一灰色，不显示因子配色。
            return manual ? Color.gray : fillColor
        }
        if manual {
            return Color.white.opacity(0.12)
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
                                      delta: ambDelta, active: ambActive, id: "ambient"),
                          manual: viewModel.lightEngine.isManual)
                    .frame(width: slot * 0.40)
                factorCol(FactorCell(icon: "iphone", label: L10n.factorPosture,
                                      delta: posDelta, active: posActive, id: "posture"),
                          manual: viewModel.lightEngine.isManual)
                    .frame(width: slot * 0.15)
                factorCol(FactorCell(icon: "moon.zzz.fill", label: L10n.factorDark,
                                      delta: darkDelta, active: darkActive, id: "dark"),
                          manual: viewModel.lightEngine.isManual)
                    .frame(width: slot * 0.15)
                factorCol(FactorCell(icon: "moon.fill", label: moonLabel,
                                      delta: moonDelta, active: moonActive, id: "moon"),
                          manual: viewModel.lightEngine.isManual)
                    .frame(width: slot * 0.15)
                factorCol(FactorCell(icon: "cloud.fill", label: weatherLabel,
                                      delta: weatherDelta, active: weatherActive, id: "weather"),
                          manual: viewModel.lightEngine.isManual)
                    .frame(width: slot * 0.15)
            }
        }
        .frame(height: 38)
        .padding(.horizontal, 12)
    }

    private func factorCol(_ cell: FactorCell, manual: Bool) -> some View {
        let boost = viewModel.uiBrightnessBoost
        return Button(action: { viewModel.toggleFactor(id: cell.id) }) {
            VStack(spacing: 1) {
                Text(cell.label)
                    .font(.gloBody(9))
                    .lineLimit(1)
                    .foregroundColor(manual ? .white.opacity(0.35)
                                            : (cell.active ? .white : .white.opacity(min(0.3 * boost, 0.7))))
                HStack(spacing: 2) {
                    // Color dot matches the factor's ring-segment color, so the
                    // deduction segments on the glow rings are traceable back to
                    // this row.
                    Circle()
                        .fill(manual ? Color.gray : factorColor(cell.id))
                        .frame(width: 4, height: 4)
                    Image(systemName: cell.icon)
                        .font(.system(size: 8))
                    Text(cell.delta > 0 ? "+\(cell.delta)%" : "\(cell.delta)%")
                        .font(.gloMono(10))
                }
                .foregroundColor(manual ? .white.opacity(0.30)
                                        : (cell.delta != 0 ? .gloAmber : .white.opacity(min(0.25 * boost, 0.6))))
            }
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(manual ? Color.gray.opacity(0.10)
                                 : (cell.active ? Color.gloAmber.opacity(min(0.08 * boost, 0.20))
                                                : Color.white.opacity(min(0.02 * boost, 0.06))))
            )
        }
        .buttonStyle(.plain)
        .disabled(manual)
        .opacity(manual ? 0.55 : min(cell.active ? 0.85 : 0.4 * boost, 1.0))
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
