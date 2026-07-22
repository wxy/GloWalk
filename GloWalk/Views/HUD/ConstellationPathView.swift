import SwiftUI

/// Real-time constellation path with bezier curves, auto-scroll, and compass.
struct ConstellationPathView: View {
    let points: [PathPoint]
    let heading: Double
    let isActive: Bool

    @State private var scrollOffset: CGFloat = 1.0 // 1.0 = show end, 0.0 = show start

    var body: some View {
        Canvas { ctx, size in
            guard points.count >= 2 else { return }

            let segmentCount = max(points.count - 1, 1)
            // Show last ~20 segments at a time, scroll to follow end
            let windowSize = min(20, segmentCount)
            let startIdx = max(0, segmentCount - windowSize)
            let visiblePoints = Array(points[max(0, startIdx - 1)...]) // +1 for control point

            guard visiblePoints.count >= 2 else { return }

            let lats = visiblePoints.map(\.latitude)
            let lons = visiblePoints.map(\.longitude)
            guard let minLat = lats.min(), let maxLat = lats.max(),
                  let minLon = lons.min(), let maxLon = lons.max() else { return }
            let latR = max(maxLat - minLat, 0.00005)
            let lonR = max(maxLon - minLon, 0.00005)

            let inset: CGFloat = 28
            let area = CGRect(x: inset, y: inset,
                              width: size.width - inset * 2,
                              height: size.height - inset * 2)

            func project(_ p: PathPoint) -> CGPoint {
                CGPoint(x: area.origin.x + CGFloat((p.longitude - minLon) / lonR) * area.width,
                        y: area.origin.y + CGFloat(1.0 - (p.latitude - minLat) / latR) * area.height)
            }

            // Draw cubic bezier segments for smooth curves
            for i in 2..<visiblePoints.count {
                let p0 = visiblePoints[i-2]
                let p1 = visiblePoints[i-1]
                let p2 = visiblePoints[i]

                let pt0 = project(p0), pt1 = project(p1), pt2 = project(p2)
                let avgLight = (p1.ambientLight + p2.ambientLight) / 2.0
                let alpha = 0.2 + (1.0 - avgLight) * 0.35
                let width = 1.5 + (1.0 - avgLight) * 2.5

                // Cubic bezier using Catmull-Rom style control points
                // cp1 is pt1 extended along pt1→pt2 tangent, influenced by pt0
                // cp2 is pt2 extended along pt2→pt1 tangent, influenced by next point
                let tension: CGFloat = 0.25
                let dx1 = pt2.x - pt0.x
                let dy1 = pt2.y - pt0.y
                let cp1 = CGPoint(x: pt1.x + dx1 * tension, y: pt1.y + dy1 * tension)

                // For cp2, use reverse vector from pt1→pt2 smoothed
                let dx2 = pt1.x - pt2.x
                let dy2 = pt1.y - pt2.y
                let cp2 = CGPoint(x: pt2.x + dx2 * tension, y: pt2.y + dy2 * tension)

                var path = Path()
                path.move(to: pt1)
                path.addCurve(to: pt2, control1: cp1, control2: cp2)

                ctx.stroke(path,
                    with: .color(Color.gloGold.opacity(alpha)),
                    style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            }

            // Start dot on first visible point
            if let first = visiblePoints.first {
                let p = project(first)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x-3, y: p.y-3, width: 6, height: 6)),
                         with: .color(.white.opacity(0.5)))
            }
            // Current position = lantern
            if let last = visiblePoints.last {
                let p = project(last)
                ctx.draw(Text("🏮").font(.system(size: 16)),
                         at: CGPoint(x: p.x, y: p.y - 10))
            }

            // Compass now shown in top-center bar, not on path
        }
        .opacity(isActive ? 0.7 : 0)
        .animation(.easeInOut(duration: 1.0), value: isActive)
    }

    // MARK: - Compass

    private func drawCompass(ctx: inout GraphicsContext, size: CGSize, heading: Double) {
        let cx = size.width - 28
        let cy: CGFloat = 28
        let r: CGFloat = 16

        ctx.stroke(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r*2, height: r*2)),
                   with: .color(.white.opacity(0.1)), lineWidth: 0.5)

        let rad = heading * .pi / 180
        let nx = cx - sin(rad) * r * 0.7
        let ny = cy - cos(rad) * r * 0.7

        var needle = Path()
        needle.move(to: CGPoint(x: nx, y: ny))
        needle.addLine(to: CGPoint(x: cx + sin(rad) * 2 + cos(rad) * 3,
                                     y: cy + cos(rad) * 2 - sin(rad) * 3))
        needle.addLine(to: CGPoint(x: cx + sin(rad) * 2 - cos(rad) * 3,
                                     y: cy + cos(rad) * 2 + sin(rad) * 3))
        needle.closeSubpath()
        ctx.fill(needle, with: .color(Color.gloGold.opacity(0.7)))
    }
}
