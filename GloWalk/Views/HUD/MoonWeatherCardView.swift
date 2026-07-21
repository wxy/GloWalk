import SwiftUI

struct MoonCardView: View {
    let data: MoonCardData
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: data.isActive ? "moon.fill" : "moon")
                    .font(.system(size: 12))
                Text(data.phaseName)
                    .font(.system(size: 12))
                Text("\(data.effectPercent)%")
                    .font(.system(size: 10))
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

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: data.isActive ? "cloud.fill" : "cloud")
                    .font(.system(size: 12))
                Text(data.condition)
                    .font(.system(size: 12))
                Text(data.effectPercent > 0 ? "+\(data.effectPercent)%" : "\(data.effectPercent)%")
                    .font(.system(size: 10))
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
