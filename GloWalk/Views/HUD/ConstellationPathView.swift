import SwiftUI

struct ConstellationPathView: View {
    let points: [PathPoint]
    let isActive: Bool

    var body: some View {
        Canvas { ctx, size in
            let inset: CGFloat = 28
            let area = CGRect(x: inset, y: inset,
                              width: size.width - inset * 2,
                              height: size.height - inset * 2)
            guard let projector = PathProjector(points: points, area: area),
                  points.count >= 2 else { return }

            // Draw bezier segments — golden constellation lines
            projector.forEachSegment { pt1, pt2, cp1, cp2, avgLight in
                let alpha = 0.35 + (1.0 - avgLight) * 0.40
                let width = 2.0 + (1.0 - avgLight) * 3.0

                var path = Path()
                path.move(to: pt1)
                path.addCurve(to: pt2, control1: cp1, control2: cp2)

                ctx.stroke(path,
                    with: .color(Color.gloGold.opacity(alpha)),
                    style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            }

            // Start — 👣 emoji at the first drawn point (second GPS point for bezier)
            let startPoint: CGPoint? = points.count >= 3
                ? projector.project(points[1])
                : projector.startPoint()
            if let sp = startPoint {
                ctx.draw(Text("👣").font(.system(size: 16)),
                         at: CGPoint(x: sp.x - 8, y: sp.y - 8))
            }

            // End — 🦶 emoji with glow aura, centered on the end point
            if let end = projector.endPoint(), points.count >= 2 {
                let glowRect = CGRect(x: end.x - 10, y: end.y - 10, width: 20, height: 20)
                ctx.fill(Path(ellipseIn: glowRect),
                         with: .color(Color.gloGold.opacity(0.18)))
                ctx.draw(Text("🦶").font(.system(size: 16)),
                         at: CGPoint(x: end.x - 8, y: end.y - 8))
            }

            // Nocturnal animal easter egg — ~3% chance, appears mid-path
            if points.count >= 6 {
                let seed = Int(points[0].latitude * 1000 + points[0].longitude * 1000)
                let hash = abs(seed.hashValue) % 100
                if hash < 3, let mid = projector.startPoint(), let endPt = projector.endPoint() {
                    let mx = (mid.x + endPt.x) / 2
                    let my = (mid.y + endPt.y) / 2 + CGFloat(hash - 1) * 3
                    let midDir = segmentDirection(from: mid, to: CGPoint(x: mx + 1, y: my))
                    let animal = hash % 3  // 0=owl, 1=fox, 2=cat
                    drawAnimal(ctx: &ctx, at: CGPoint(x: mx, y: my),
                               angle: midDir, kind: animal)
                }
            }
        }
        .opacity(isActive ? 0.85 : 0)
        .animation(.easeInOut(duration: 1.0), value: isActive)
    }

    /// Direction angle from pt1 to pt2 (radians, 0 = right)
    private func segmentDirection(from pt1: CGPoint, to pt2: CGPoint) -> CGFloat {
        atan2(pt2.y - pt1.y, pt2.x - pt1.x)
    }

    // MARK: - Animal Easter Eggs

    /// Draw a tiny nocturnal animal silhouette at `point`, rotated by `angle`.
    /// `kind`: 0=owl, 1=fox, 2=cat
    private func drawAnimal(ctx: inout GraphicsContext, at point: CGPoint,
                             angle: CGFloat, kind: Int) {
        let transform = CGAffineTransform.identity
            .translatedBy(x: point.x, y: point.y)
            .rotated(by: angle)
        let path: Path
        switch kind {
        case 0: path = owlPath()
        case 1: path = foxPath()
        default: path = catPath()
        }
        ctx.fill(path.applying(transform),
                 with: .color(Color.gloGold.opacity(0.25)))
    }

    /// Simple owl silhouette — round body, ear tufts, big eyes hint
    private func owlPath() -> Path {
        var p = Path()
        let s: CGFloat = 8
        // Body
        p.addEllipse(in: CGRect(x: -s*0.6, y: -s*0.3, width: s*1.2, height: s*1.3))
        // Ear tufts
        p.move(to: CGPoint(x: -s*0.5, y: -s*0.3))
        p.addLine(to: CGPoint(x: -s*0.7, y: -s*0.8))
        p.addLine(to: CGPoint(x: -s*0.2, y: -s*0.3))
        p.move(to: CGPoint(x: s*0.5, y: -s*0.3))
        p.addLine(to: CGPoint(x: s*0.7, y: -s*0.8))
        p.addLine(to: CGPoint(x: s*0.2, y: -s*0.3))
        return p
    }

    /// Simple fox silhouette — pointed snout, big ears, bushy tail
    private func foxPath() -> Path {
        var p = Path()
        let s: CGFloat = 7
        // Body
        p.addEllipse(in: CGRect(x: -s*0.5, y: -s*0.3, width: s*1.0, height: s*1.2))
        // Pointed ears (triangles)
        p.move(to: CGPoint(x: -s*0.4, y: -s*0.3))
        p.addLine(to: CGPoint(x: -s*0.55, y: -s*0.9))
        p.addLine(to: CGPoint(x: -s*0.1, y: -s*0.3))
        p.move(to: CGPoint(x: s*0.4, y: -s*0.3))
        p.addLine(to: CGPoint(x: s*0.55, y: -s*0.9))
        p.addLine(to: CGPoint(x: s*0.1, y: -s*0.3))
        // Bushy tail
        p.addEllipse(in: CGRect(x: s*0.3, y: s*0.2, width: s*0.8, height: s*0.5))
        return p
    }

    /// Simple cat silhouette — round head, pointy ears, curved tail
    private func catPath() -> Path {
        var p = Path()
        let s: CGFloat = 7
        // Body
        p.addEllipse(in: CGRect(x: -s*0.5, y: -s*0.2, width: s*1.0, height: s*1.1))
        // Round head
        p.addEllipse(in: CGRect(x: -s*0.4, y: -s*0.7, width: s*0.8, height: s*0.7))
        // Pointy ears
        p.move(to: CGPoint(x: -s*0.3, y: -s*0.7))
        p.addLine(to: CGPoint(x: -s*0.35, y: -s*1.0))
        p.addLine(to: CGPoint(x: -s*0.05, y: -s*0.7))
        p.move(to: CGPoint(x: s*0.3, y: -s*0.7))
        p.addLine(to: CGPoint(x: s*0.35, y: -s*1.0))
        p.addLine(to: CGPoint(x: s*0.05, y: -s*0.7))
        // Curled tail
        p.addArc(center: CGPoint(x: s*0.5, y: s*0.2), radius: s*0.3,
                 startAngle: .degrees(0), endAngle: .degrees(270), clockwise: true)
        return p
    }
}
