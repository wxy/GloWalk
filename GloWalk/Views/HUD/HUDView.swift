import SwiftUI

struct HUDView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            Color.gloBlack.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Central glow — placeholder for lantern animation
                Circle()
                    .stroke(Color.gloAmber.opacity(0.4), lineWidth: 2)
                    .frame(width: 100, height: 100)
                    .overlay(
                        Circle()
                            .fill(Color.gloAmber.opacity(0.2))
                            .frame(width: 60, height: 60)
                    )
                    .overlay(
                        Text("GloWalk")
                            .font(.system(size: 12))
                            .foregroundColor(.gloAmber.opacity(0.6))
                    )

                Spacer()

                Text("步行手电筒")
                    .font(.system(size: 14))
                    .foregroundColor(.gloAmber.opacity(0.5))
                    .padding(.bottom, 48)
            }
        }
        .gloWalkHUD()
    }
}
