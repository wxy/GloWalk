import SwiftUI

struct GlowCircleView: View {
    let brightness: Double
    let isManual: Bool

    @State private var breathe: Double = 0

    private var warmth: Double { brightness }

    var body: some View {
        ZStack {
            // Layer 1: Ambient light field — radial glow
            RadialGradient(
                colors: [
                    Color.gloTorchCore.opacity(0.08 * warmth),
                    Color.gloGold.opacity(0.03 * warmth),
                    .clear
                ],
                center: .center,
                startRadius: 15,
                endRadius: 120
            )
            .frame(width: 240, height: 240)

            // Layer 2: Mid glow
            RadialGradient(
                colors: [
                    Color.gloTorchCore.opacity(0.18 * warmth),
                    Color.gloGold.opacity(0.06 * warmth),
                    .clear
                ],
                center: .center,
                startRadius: 5,
                endRadius: 70
            )
            .frame(width: 140, height: 140)

            // Layer 3: Inner bright core
            RadialGradient(
                colors: [
                    Color.gloTorchCore.opacity(0.35 * warmth),
                    Color.gloGold.opacity(0.12 * warmth),
                    .clear
                ],
                center: .center,
                startRadius: 0,
                endRadius: 35
            )
            .frame(width: 70, height: 70)

            // Layer 4: Subtle guide ring at the edge of visibility
            Circle()
                .stroke(
                    Color.gloGold.opacity(0.2 * warmth),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 10])
                )
                .frame(width: 90, height: 90)

            // Brightness percentage — clean, centered
            Text("\(Int(brightness * 100))%")
                .font(.gloDisplay(22))
                .fontWeight(.light)
                .foregroundColor(isManual ? .white : Color.gloTorchCore)
                .shadow(color: (isManual ? Color.white : Color.gloGold).opacity(0.5 * warmth), radius: 12, x: 0, y: 0)
        }
        .scaleEffect(0.95 + breathe * 0.05)
        .opacity(0.85 + breathe * 0.15)
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                breathe = 1
            }
        }
    }
}
