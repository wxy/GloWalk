import SwiftUI

struct GlowCircleView: View {
    let brightness: Double
    let isManual: Bool
    let cadence: Double
    let isPaused: Bool

    @State private var breathe: Double = 0
    @State private var stepPhase: Double = 0

    private var warmth: Double { brightness }

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

            // Layer 3: Guide ring — subtle boundary at the edge of glow
            Circle()
                .stroke(
                    Color.gloGold.opacity(0.18 * warmth),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 10])
                )
                .frame(width: 100, height: 100)

            // Brightness percentage — with strikethrough overlay when paused
            Text("\(Int(brightness * 100))%")
                // .gloDisplay is already "LXGW WenKai Light" — do NOT add
                // .fontWeight(.light), it re-weights the descriptor and logs
                // "Unable to update Font Descriptor's weight".
                .font(.gloDisplay(22))
                .foregroundColor(isPaused ? .white.opacity(0.25)
                                 : isManual ? .white : Color.gloTorchCore)
                .shadow(color: isPaused ? .clear
                         : (isManual ? Color.white : Color.gloGold).opacity(0.5 * warmth),
                         radius: 12, x: 0, y: 0)
                .overlay {
                    if isPaused {
                        Rectangle()
                            .fill(.white.opacity(0.25))
                            .frame(height: 1)
                            .frame(width: 44)
                    }
                }
                .offset(y: 64)

            // Operation hints — breathe with the glow
            VStack(spacing: 4) {
                Text(L10n.isZh
                     ? "双击结束步行    长按开关灯光"
                     : "Double-tap to end, long-press for torch")
                Text(L10n.isZh
                     ? "滑动调整亮度    单击恢复自动"
                     : "Swipe to adjust, tap to restore")
            }
            .font(.gloBody(11))
            .foregroundColor(.white.opacity(0.5))
            .offset(y: 100)
        }
        // Breathing + rhythm pulse: gentle breath at 3s cycle, subtle step-sync flutter
        .scaleEffect(0.95 + breathe * 0.05 + cadence * 0.02 * sin(stepPhase))
        .opacity(0.85 + breathe * 0.15 + cadence * 0.04 * sin(stepPhase))
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
