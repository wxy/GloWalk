import SwiftUI
import CoreLocation

/// Real-time constellation path with direction arrows and compass.
struct ConstellationPathView: View {
    let points: [PathPoint]
    let heading: Double?   // device heading in degrees (0=north, 90=east)
    let isActive: Bool

    var body: some View {
        Canvas { ctx, size in
            guard points.count >= 2 else { return }

            let lats = points.map(\.latitude); let lons = points.map(\.longitude)
            guard let minLat = lats.min(), let maxLat = lats.max(),
                  let minLon = lons.min(), let maxLon = lons.max() else { return }
            let latR = max(maxLat - minLat, 0.0001)
            let lonR = max(maxLon - minLon, 0.0001)

            let inset: CGFloat = 28
            let area = CGRect(x: inset, y: inset,
                              width: size.width - inset * 2,
                              height: size.height - inset * 2)

            func project(_ p: PathPoint) -> CGPoint {
                CGPoint(x: area.origin.x + CGFloat((p.longitude - minLon) / lonR) * area.width,
                        y: area.origin.y + CGFloat(1.0 - (p.latitude - minLat) / latR) * area.height)
            }

            // Draw path segments with arrowheads
            for i in 1..<points.count {
                let prev = project(points[i-1])
                let curr = project(points[i])
                let avgLight = (points[i-1].ambientLight + points[i].ambientLight) / 2.0

                let alpha = 0.2 + (1.0 - avgLight) * 0.35
                let width = 1.5 + (1.0 - avgLight) * 2.5

                var path = Path()
                path.move(to: prev); path.addLine(to: curr)
                ctx.stroke(path,
                    with: .color(Color.gloGold.opacity(alpha)),
                    style: StrokeStyle(lineWidth: width, lineCap: .round))

                // Direction arrow at midpoint every 2nd segment
                if i % 2 == 0 {
                    let mid = CGPoint(x: (prev.x + curr.x)/2, y: (prev.y + curr.y)/2)
                    let angle = atan2(curr.y - prev.y, curr.x - prev.x)
                    drawArrowhead(ctx: &ctx, at: mid, angle: angle,
                                  color: Color.gloGold.opacity(alpha * 1.3))
                }
            }

            // Start dot
            if let first = points.first {
                let p = project(first)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x-3, y: p.y-3, width: 6, height: 6)),
                         with: .color(.white.opacity(0.6)))
            }
            // End star
            if points.count >= 2, let last = points.last {
                let p = project(last)
                ctx.fill(starPath(center: p, radius: 5),
                         with: .color(Color.gloGold.opacity(0.8)))
            }

            // Compass rose
            drawCompass(ctx: &ctx, size: size, heading: heading ?? 0)
        }
        .opacity(isActive ? 0.7 : 0)
        .animation(.easeInOut(duration: 1.0), value: isActive)
    }

    // MARK: - Arrowhead

    private func drawArrowhead(ctx: inout GraphicsContext, at center: CGPoint,
                                angle: CGFloat, color: Color) {
        let len: CGFloat = 5
        let spread: CGFloat = 0.6
        var arrow = Path()
        let tip = CGPoint(x: center.x + cos(angle) * len,
                          y: center.y + sin(angle) * len)
        let left = CGPoint(x: center.x + cos(angle + .pi - spread) * len * 0.6,
                            y: center.y + sin(angle + .pi - spread) * len * 0.6)
        let right = CGPoint(x: center.x + cos(angle + .pi + spread) * len * 0.6,
                             y: center.y + sin(angle + .pi + spread) * len * 0.6)
        arrow.move(to: tip); arrow.addLine(to: left); arrow.addLine(to: right)
        arrow.closeSubpath()
        ctx.fill(arrow, with: .color(color))
    }

    // MARK: - Compass

    private func drawCompass(ctx: inout GraphicsContext, size: CGSize, heading: Double) {
        let cx = size.width - 30
        let cy: CGFloat = 30
        let r: CGFloat = 18

        // Compass circle
        ctx.stroke(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r*2, height: r*2)),
                   with: .color(.white.opacity(0.12)), lineWidth: 0.5)

        // North pointer (rotates with heading)
        let rad = heading * .pi / 180
        let nx = cx - sin(rad) * r * 0.7  // project: heading 0=north → point UP on screen
        let ny = cy - cos(rad) * r * 0.7

        var needle = Path()
        needle.move(to: CGPoint(x: nx, y: ny))
        needle.addLine(to: CGPoint(x: cx + sin(rad) * 3 + cos(rad) * 4,
                                     y: cy + cos(rad) * 3 - sin(rad) * 4))
        needle.addLine(to: CGPoint(x: cx + sin(rad) * 3 - cos(rad) * 4,
                                     y: cy + cos(rad) * 3 + sin(rad) * 4))
        needle.closeSubpath()
        ctx.fill(needle, with: .color(Color.gloGold.opacity(0.7)))

        // N mark
        let markSize: CGFloat = 7
        ctx.draw(Text("N").font(.system(size: 7)).foregroundColor(.white.opacity(0.3)),
                 at: CGPoint(x: cx, y: cy - r - markSize))
    }

    // MARK: - Star

    private func starPath(center: CGPoint, radius: CGFloat) -> Path {
        var p = Path()
        for i in 0..<5 {
            let a = CGFloat(i) * .pi * 2 / 5 - .pi / 2
            let x = center.x + cos(a) * radius
            let y = center.y + sin(a) * radius
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
            else { p.addLine(to: CGPoint(x: x, y: y)) }
            let ia = a + .pi / 5
            p.addLine(to: CGPoint(x: center.x + cos(ia) * radius * 0.4,
                                   y: center.y + sin(ia) * radius * 0.4))
        }
        p.closeSubpath()
        return p
    }
}
