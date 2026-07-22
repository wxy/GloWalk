import SwiftUI

struct GlowCircleView: View {
    let brightness: Double

    var body: some View {
        ZStack {
            // Farthest glow — very wide, very faint
            Circle()
                .fill(Color.gloGold.opacity(0.04 * brightness))
                .frame(width: 240, height: 240)
                .blur(radius: 40)

            // Outer glow ring
            Circle()
                .fill(Color.gloGold.opacity(0.08 * brightness))
                .frame(width: 160, height: 160)
                .blur(radius: 20)

            // Dashed ring
            Circle()
                .stroke(
                    Color.gloGold.opacity(0.35 * brightness),
                    style: StrokeStyle(lineWidth: 2, dash: [4, 8])
                )
                .frame(width: 100, height: 100)

            // Inner filled circle
            Circle()
                .fill(Color.gloGold.opacity(0.18 * brightness))
                .frame(width: 60, height: 60)

            // Brightness %
            Text("\(Int(brightness * 100))%")
                .font(.system(size: 28, weight: .light, design: .rounded))
                .foregroundColor(.gloGold)
        }
        .animation(.easeInOut(duration: 0.5), value: brightness)
    }
}
