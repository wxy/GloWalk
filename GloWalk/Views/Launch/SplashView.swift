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
                Text("🏮")
                    .font(.system(size: 44))

                Text(tagline.localizedPhrase)
                    .font(.gloHeadline(17))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(4)

                Text(tagline.localizedExplanation)
                    .font(.gloBody(11))
                    .foregroundColor(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .opacity(opacity)
        .onAppear {
            if isQuickLaunch { onComplete(); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
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
