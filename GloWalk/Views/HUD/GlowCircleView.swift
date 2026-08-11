import SwiftUI

struct GlowCircleView: View {
    let brightness: Double
    let cadence: Double
    let isPaused: Bool
    /// 拖动调亮度时图标强制最大亮度，保证控件清晰可见；
    /// 其他元素（亮度条/因素行）仍按实际亮度显示。
    let isDragging: Bool

    @State private var breathe: Double = 0
    @State private var stepPhase: Double = 0
    /// 操作提示是否可见：刚进入时显示，几秒后自动淡出。
    @State private var showHints = true

    private var warmth: Double { isDragging ? 1.0 : brightness }

    /// Icon opacity scales with brightness:
    /// dim torch → ghost outline; full torch → clearly visible brand mark.
    private var iconOpacity: Double { 0.20 + warmth * 0.70 }

    var body: some View {
        ZStack {
            // Layer 0: App icon — the central visual element.
            // The icon already has a grainy glow texture, so it replaces
            // the inner core glow and serves as the lantern itself.
            Image(uiImage: UIImage(named: "AppLogo") ?? UIImage())
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 90, height: 90)
                .cornerRadius(20)
                .opacity(iconOpacity)

            // Layer 1: Ambient halo — wide soft glow behind the icon
            RadialGradient(
                colors: [
                    Color.gloTorchCore.opacity(0.06 * warmth),
                    Color.gloGold.opacity(0.02 * warmth),
                    .clear
                ],
                center: .center,
                startRadius: 30,
                endRadius: 120
            )
            .frame(width: 240, height: 240)

            // Layer 2: Mid halo — warm aura around the icon
            RadialGradient(
                colors: [
                    Color.gloTorchCore.opacity(0.14 * warmth),
                    Color.gloGold.opacity(0.05 * warmth),
                    .clear
                ],
                center: .center,
                startRadius: 20,
                endRadius: 80
            )
            .frame(width: 160, height: 160)

            // Operation hints — breathe with the glow
            VStack(spacing: 4) {
                Text(L10n.hintEndWalk)
                Text(L10n.hintAdjust)
            }
            .font(.gloBody(11))
            .foregroundColor(.white.opacity(0.5))
            .offset(y: 100)
            .opacity(showHints ? 1 : 0)
        }
        // Breathing + rhythm pulse: gentle breath at 3s cycle, subtle step-sync flutter
        .scaleEffect(0.95 + breathe * 0.05 + cadence * 0.02 * sin(stepPhase))
        .opacity(0.85 + breathe * 0.15 + cadence * 0.04 * sin(stepPhase))
        // 暂停时整体变暗，让"手电已关"的状态一眼可见。
        .opacity(isPaused ? 0.45 : 1.0)
        .overlay {
            if isPaused {
                Image(systemName: "pause.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.black)
                    .padding(6)
                    .background(Circle().fill(Color.gloGold))
                    .offset(x: 42, y: -42)
            }
        }
        .task {
            // 操作提示：刚进入时显示，8 秒后自动淡出，避免长期占据视线。
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            withAnimation(.easeOut(duration: 1.0)) { showHints = false }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                breathe = 1
            }
        }
        .onChange(of: cadence) { _ in
            if cadence > 0.1 {
                withAnimation(.easeInOut(duration: 0.5 / max(cadence, 0.3)).repeatForever(autoreverses: false)) {
                    stepPhase += .pi * 2
                }
            }
        }
    }

}
