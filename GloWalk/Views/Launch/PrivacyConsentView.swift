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

                Text("你的隐私")
                    .font(.gloHeadline(28))
                    .foregroundColor(.white)

                VStack(alignment: .leading, spacing: 16) {
                    privacyItem("camera.fill",
                        "摄像头仅用于感知环境光线，不拍照、不录像、不存储画面")
                    privacyItem("location.fill",
                        "路径数据只存于你的手机，不会上传到任何服务器")
                    privacyItem("eye.slash.fill",
                        "没有广告、没有追踪、没有第三方 SDK")
                    privacyItem("hand.raised.fill",
                        "你可以随时在设置中关闭任何权限")
                }
                .padding(.horizontal, 32)

                Spacer()

                Button(action: { hasCompletedOnboarding = true }) {
                    Text("开始使用")
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

    private func privacyItem(_ icon: String, _ text: String) -> some View {
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
