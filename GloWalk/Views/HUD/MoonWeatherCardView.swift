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
                Image(systemName: isActive ? icon : "\(icon)")
                    .font(.system(size: 9))
                Text(label)
                    .font(.gloBody(9))
                    .lineLimit(1)
                if brightnessDelta != 0 {
                    Text(brightnessDelta > 0 ? "+\(brightnessDelta)%" : "\(brightnessDelta)%")
                        .font(.system(size: 8))
                        .foregroundColor(.gloAmber)
                }
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

// MARK: - Moon Card

struct MoonCardView: View {
    let data: MoonCardData
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 3) {
                Image(systemName: data.isActive ? "moon.fill" : "moon")
                    .font(.gloBody(11))
                Text(data.phaseName)
                    .font(.gloBody(11))
                    .lineLimit(1).minimumScaleFactor(0.65)
                if data.brightnessDelta != 0 {
                    Text(data.brightnessDelta > 0 ? "+\(data.brightnessDelta)%" : "\(data.brightnessDelta)%")
                        .font(.gloBody(9))
                        .foregroundColor(.gloAmber)
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(data.isActive ? Color.gloAmber.opacity(0.12) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(data.isActive ? 0.08 : 0.03), lineWidth: 0.5)
            )
            .opacity(data.isActive ? 0.9 : 0.4)
        }
        .buttonStyle(.plain)
    }
}

struct WeatherCardView: View {
    let data: WeatherCardData
    let onTap: () -> Void

    private var providerTint: Color {
        switch data.provider {
        case .apple:     return Color.gloGold.opacity(0.15)
        case .openMeteo: return Color.gloGold.opacity(0.10)
        case .none:      return Color.white.opacity(0.05)
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 3) {
                Circle()
                    .fill(data.provider == .apple ? Color.gloGold : Color.gloGold.opacity(0.5))
                    .frame(width: 4, height: 4)
                    .opacity(data.isActive ? 1 : 0.3)

                Image(systemName: data.isActive ? "cloud.fill" : "cloud")
                    .font(.gloBody(11))
                Text(data.condition)
                    .font(.gloBody(11))
                    .lineLimit(1).minimumScaleFactor(0.65)
                if data.brightnessDelta != 0 {
                    Text(data.brightnessDelta > 0 ? "+\(data.brightnessDelta)%" : "\(data.brightnessDelta)%")
                        .font(.gloBody(9))
                        .foregroundColor(.gloAmber)
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(providerTint)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(data.isActive ? 0.08 : 0.03), lineWidth: 0.5)
            )
            .opacity(data.isActive ? 0.9 : 0.4)
        }
        .buttonStyle(.plain)
    }
}
