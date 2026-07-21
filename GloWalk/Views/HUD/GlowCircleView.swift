import SwiftUI

struct GlowCircleView: View {
    let brightness: Double

    var body: some View {
        ZStack {
            // Outer glow halo
            Circle()
                .stroke(Color.gloAmber.opacity(0.15 * brightness), lineWidth: 2)
                .frame(width: 120, height: 120)
                .blur(radius: 4)

            // Dashed ring
            Circle()
                .stroke(
                    Color.gloAmber.opacity(0.4 * brightness),
                    style: StrokeStyle(lineWidth: 2, dash: [4, 8])
                )
                .frame(width: 100, height: 100)

            // Inner filled circle
            Circle()
                .fill(Color.gloAmber.opacity(0.2 * brightness))
                .frame(width: 60, height: 60)

            // Brightness percentage
            Text("\(Int(brightness * 100))%")
                .font(.system(size: 28, weight: .light, design: .rounded))
                .foregroundColor(.gloAmber)
        }
        .animation(.easeInOut(duration: 0.5), value: brightness)
    }
}
