import SwiftUI
import UIKit

struct MoonPhaseHUDView: View {
    let brightness: Double

    private var moonImage: UIImage? {
        PosterGenerator.currentMoonImage()
    }

    var body: some View {
        ZStack {
            // Moon phase image from NASA
            if let img = moonImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .opacity(0.35 + brightness * 0.4) // brighter when torch is brighter
                    .clipShape(Circle())
            } else {
                // Fallback: simple glow circle
                Circle()
                    .fill(Color.gloGold.opacity(0.15 * brightness))
                    .frame(width: 160, height: 160)
                    .blur(radius: 20)
            }

            // Brightness ring
            Circle()
                .stroke(
                    Color.gloGold.opacity(0.3 * brightness),
                    style: StrokeStyle(lineWidth: 2, dash: [4, 8])
                )
                .frame(width: 200, height: 200)

            // Brightness %
            Text("\(Int(brightness * 100))%")
                .font(.gloDisplay(28))
                .foregroundColor(.gloGold)
                .shadow(color: .black.opacity(0.8), radius: 4)
        }
        .animation(.easeInOut(duration: 0.5), value: brightness)
    }
}
