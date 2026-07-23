import SwiftUI

struct PrivacyConsentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        ZStack {
            Color.gloBlack.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                Image(systemName: "hand.raised.fill")
                    .font(.gloBody(48))
                    .foregroundColor(.gloAmber)

                Text(L10n.privacyTitle)
                    .font(.gloHeadline(28))
                    .foregroundColor(.white)

                VStack(alignment: .leading, spacing: 16) {
                    privacyItem("camera.fill", L10n.privacyItem1)
                    privacyItem("location.fill", L10n.privacyItem2)
                    privacyItem("eye.slash.fill", L10n.privacyItem3)
                    privacyItem("hand.raised.fill", L10n.privacyItem4)
                }
                .padding(.horizontal, 32)

                Spacer()

                Button(action: { hasCompletedOnboarding = true }) {
                    Text(L10n.privacyStart)
                        .font(.gloHeadline(17))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.gloAmber)
                        .cornerRadius(20)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            }
        }
    }

    private func privacyItem(_ icon: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.gloAmber)
                .frame(width: 24)
            Text(text)
                .font(.gloBody(14))
                .foregroundColor(.white.opacity(0.8))
        }
    }
}
