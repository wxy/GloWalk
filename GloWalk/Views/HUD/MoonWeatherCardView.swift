import SwiftUI

// MARK: - Generic Factor Card

struct FactorCardView: View {
    let icon: String
    let label: String
    let brightnessDelta: Int
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                Text(label)
                    .font(.system(size: 9))
                    .lineLimit(1)
                Text(brightnessDelta > 0 ? "+\(brightnessDelta)%" : "\(brightnessDelta)%")
                    .font(.system(size: 9))
                    .foregroundColor(brightnessDelta != 0 ? .gloAmber : .white.opacity(0.3))
            }
            .padding(.horizontal, 5).padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? Color.gloAmber.opacity(0.10) : Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(isActive ? 0.06 : 0.02), lineWidth: 0.5)
            )
            .opacity(isActive ? 0.85 : 0.35)
        }
        .buttonStyle(.plain)
    }
}

