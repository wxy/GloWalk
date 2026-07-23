import SwiftUI

struct ConstellationPathView: View {
    let points: [PathPoint]
    let heading: Double
    let isActive: Bool

    var body: some View {
        Canvas { ctx, size in
            let inset: CGFloat = 28
            let area = CGRect(x: inset, y: inset,
                              width: size.width - inset * 2,
                              height: size.height - inset * 2)
            guard let projector = PathProjector(points: points, area: area),
                  points.count >= 2 else { return }

            // Draw bezier segments
            projector.forEachSegment { pt1, pt2, cp1, cp2, avgLight in
                let alpha = 0.2 + (1.0 - avgLight) * 0.35
                let width = 1.5 + (1.0 - avgLight) * 2.5

                var path = Path()
                path.move(to: pt1)
                path.addCurve(to: pt2, control1: cp1, control2: cp2)

                ctx.stroke(path,
                    with: .color(Color.gloGold.opacity(alpha)),
                    style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            }

            // Start dot
            if let start = projector.startPoint() {
                ctx.fill(Path(ellipseIn: CGRect(x: start.x-3, y: start.y-3, width: 6, height: 6)),
                         with: .color(.white.opacity(0.5)))
            }
            // Current position = lantern
            if let end = projector.endPoint() {
                ctx.draw(Text("🏮").font(.system(size: 16)),
                         at: CGPoint(x: end.x, y: end.y - 10))
            }

        }
        .opacity(isActive ? 0.7 : 0)
        .animation(.easeInOut(duration: 1.0), value: isActive)
    }

    private func drawCompass(ctx: inout GraphicsContext, size: CGSize, heading: Double) {
        let cx = size.width - 28, cy: CGFloat = 28, r: CGFloat = 16
        ctx.stroke(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r*2, height: r*2)),
                   with: .color(.white.opacity(0.1)), lineWidth: 0.5)
        let rad = heading * .pi / 180
        let nx = cx - sin(rad) * r * 0.7, ny = cy - cos(rad) * r * 0.7
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
