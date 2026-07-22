import SwiftUI

struct PulsingHint: View {
    let text: String
    @State private var opacity: Double = 0.2

    var body: some View {
        Text(text)
            .font(.gloHeadline(12))
            .foregroundColor(.gloGold.opacity(opacity))
            .onAppear {
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    opacity = 0.7
                }
            }
    }
}
