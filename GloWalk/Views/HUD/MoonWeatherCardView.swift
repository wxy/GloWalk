import SwiftUI

struct MoonCardView: View {
    let data: MoonCardData
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: data.isActive ? "moon.fill" : "moon")
                    .font(.gloBody(12))
                Text(data.phaseName)
                    .font(.gloBody(12))
                Text("\(data.effectPercent)%")
                    .font(.gloBody(10))
                    .foregroundColor(.gloAmber)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(data.isActive
                          ? Color.gloAmber.opacity(0.15)
                          : Color.white.opacity(0.05))
            )
            .opacity(data.isActive ? 0.8 : 0.4)
        }
        .buttonStyle(.plain)
    }
}

struct WeatherCardView: View {
    let data: WeatherCardData
    let onTap: () -> Void

    /// Subtle background tint per provider — barely visible, mainly for dev awareness
    private var providerTint: Color {
        switch data.provider {
        case .apple:     return Color.gloGold.opacity(0.15)    // warmer gold
        case .openMeteo: return Color.gloGold.opacity(0.10)    // slightly cooler
        case .none:      return Color.white.opacity(0.05)
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                // Tiny provider indicator dot
                Circle()
                    .fill(data.provider == .apple ? Color.gloGold : Color.gloGold.opacity(0.5))
                    .frame(width: 4, height: 4)
                    .opacity(data.isActive ? 1 : 0.3)

                Image(systemName: data.isActive ? "cloud.fill" : "cloud")
                    .font(.gloBody(12))
                Text(data.condition)
                    .font(.gloBody(12))
                Text(data.effectPercent > 0 ? "+\(data.effectPercent)%" : "\(data.effectPercent)%")
                    .font(.gloBody(10))
                    .foregroundColor(.gloAmber)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(providerTint)
            )
            .opacity(data.isActive ? 0.8 : 0.4)
        }
        .buttonStyle(.plain)
    }
}
