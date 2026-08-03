import SwiftUI

struct HelpView: View {
    var body: some View {
        ZStack {
            Color.gloBlackSurface.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    helpItem(icon: "rays",
                             title: L10n.helpAutoTitle, desc: L10n.helpAutoDesc)
                    helpItem(icon: "hand.draw",
                             title: L10n.helpDragTitle, desc: L10n.helpDragDesc)
                    helpItem(icon: "hand.tap",
                             title: L10n.helpLongPressTitle, desc: L10n.helpLongPressDesc)
                    helpItem(icon: "rectangle.3.group",
                             title: L10n.helpTogglesTitle, desc: L10n.helpTogglesDesc)
                    helpItem(icon: "hand.tap.fill",
                             title: L10n.helpEndTitle, desc: L10n.helpEndDesc)
                    helpItem(icon: "arrow.down",
                             title: L10n.helpDismissTitle, desc: L10n.helpDismissDesc)
                    helpItem(icon: "clock.arrow.circlepath",
                             title: L10n.helpHistoryTitle, desc: L10n.helpHistoryDesc)
                }
                .padding(20)
            }
        }
        .navigationTitle(L10n.helpNavTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func helpItem(icon: String, title: LocalizedStringKey,
                          desc: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(.gloGold)
                    .frame(width: 20)
                Text(title)
                    .font(.gloHeadline(14))
                    .foregroundColor(.white)
            }
            Text(desc)
                .font(.gloBody(12))
                .foregroundColor(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 26)
        }
    }
}
