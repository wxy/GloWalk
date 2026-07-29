import SwiftUI

struct HelpView: View {
    var body: some View {
        ZStack {
            Color.gloBlackSurface.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    helpItem(
                        icon: "rays",
                        title: zh ? "自动调光" : "Auto Brightness",
                        desc: zh
                            ? "GloWalk 通过后置摄像头感知环境明暗，结合手机姿态、暗适应、月相和天气，实时计算最合适的亮度。无需手动操作。"
                            : "GloWalk senses ambient brightness via the rear camera and combines phone posture, dark adaptation, moon phase, and weather to compute optimal brightness in real time. No manual input needed."
                    )
                    helpItem(
                        icon: "hand.draw",
                        title: zh ? "滑动调节亮度" : "Drag to Adjust",
                        desc: zh
                            ? "在光晕区域上下滑动手指，可手动调节亮度。松开后保持当前亮度。单击光晕区域的百分比数字，恢复自动调光。"
                            : "Drag up or down on the glow circle to manually adjust brightness. The level holds after release. Tap the percentage number to return to auto mode."
                    )
                    helpItem(
                        icon: "hand.tap",
                        title: zh ? "长按关灯" : "Long Press to Pause",
                        desc: zh
                            ? "长按光晕区域 0.8 秒，可临时关闭手电筒，不结束步行。再次长按恢复。关灯时百分比显示删除线。"
                            : "Long-press the glow circle for 0.8 seconds to temporarily turn off the flashlight without ending your walk. Long-press again to resume. The percentage shows a strikethrough when paused."
                    )
                    helpItem(
                        icon: "square.grid.3x3",
                        title: zh ? "因素开关" : "Factor Toggles",
                        desc: zh
                            ? "底部五个因素卡片均可点击开关。关闭后该因素不再影响亮度计算，数值归零变灰。卡片宽度反映其在亮度决策中的权重——环境光最宽（40%），其余四个各 15%。"
                            : "Tap any of the five factor cards at the bottom to toggle it. When off, it no longer affects brightness and its delta goes to zero. Card width reflects weight — Ambient is widest (40%), others 15% each."
                    )
                    helpItem(
                        icon: "hand.tap.fill",
                        title: zh ? "双击结束步行" : "Double Tap to End",
                        desc: zh
                            ? "双击光晕区域结束本次步行，自动生成夜路海报。若步数为零，步行不会记录。"
                            : "Double-tap the glow circle to end your walk and generate a night poster. Walks with zero steps are not recorded."
                    )
                    helpItem(
                        icon: "arrow.down",
                        title: zh ? "关闭海报" : "Dismiss Poster",
                        desc: zh
                            ? "在海报页面向下滑动即可关闭，返回步行历史。"
                            : "Swipe down on the poster to dismiss it and return to walk history."
                    )
                    helpItem(
                        icon: "clock.arrow.circlepath",
                        title: zh ? "查看历史海报" : "View Past Posters",
                        desc: zh
                            ? "步行历史中点击任意记录，可重新查看和分享该次步行的夜路海报。"
                            : "Tap any walk in your history to view and share its night poster again."
                    )
                }
                .padding(20)
            }
        }
        .navigationTitle(zh ? "使用帮助" : "Help")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func helpItem(icon: String, title: String, desc: String) -> some View {
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

    private var zh: Bool { L10n.isZh }
}
