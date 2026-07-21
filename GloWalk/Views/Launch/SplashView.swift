import SwiftUI

struct SplashView: View {
    let isQuickLaunch: Bool
    let onComplete: () -> Void

    @State private var opacity: Double = 1.0
    private let tagline = Tagline.random()

    var body: some View {
        ZStack {
            Color.gloBlackCard.ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "flashlight.on.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.gloAmber)

                Text(tagline.phrase)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text(tagline.explanation)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .opacity(opacity)
        .onAppear {
            if isQuickLaunch { onComplete(); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation(.easeOut(duration: 0.5)) { opacity = 0 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { onComplete() }
            }
        }
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.3)) { opacity = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onComplete() }
        }
    }
}
