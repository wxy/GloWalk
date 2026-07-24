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
                let alpha = 0.2 + (1.0 - avgLight) * 0.35
                let width = 1.5 + (1.0 - avgLight) * 2.5

                var path = Path()
                path.move(to: pt1)
                path.addCurve(to: pt2, control1: cp1, control2: cp2)

                ctx.stroke(path,
                    with: .color(Color.gloGold.opacity(alpha)),
                    style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            }

            // Start — left footprint pointing along first segment direction
            if let start = projector.startPoint() {
                let direction = segmentDirection(from: projector.project(points[0]),
                                                  to: projector.project(points[1]))
                drawFootprint(ctx: &ctx, at: start, angle: direction, isLeft: true)
            }

            // End — right footprint pointing along last segment direction
            if let end = projector.endPoint(), points.count >= 2 {
                let direction = segmentDirection(from: projector.project(points[points.count - 2]),
                                                  to: projector.project(points[points.count - 1]))
                // Glow aura behind the footprint
                let glowRect = CGRect(x: end.x - 9, y: end.y - 9, width: 18, height: 18)
                ctx.fill(Path(ellipseIn: glowRect),
                         with: .color(Color.gloGold.opacity(0.18)))
                drawFootprint(ctx: &ctx, at: end, angle: direction, isLeft: false)
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
        .opacity(isActive ? 0.7 : 0)
        .animation(.easeInOut(duration: 1.0), value: isActive)
    }

    /// Direction angle from pt1 to pt2 (radians, 0 = right)
    private func segmentDirection(from pt1: CGPoint, to pt2: CGPoint) -> CGFloat {
        atan2(pt2.y - pt1.y, pt2.x - pt1.x)
    }

    /// Draw a simplified footprint silhouette transformed to `point` + `angle`.
    /// `isLeft` draws normally; right foot is mirrored via scaleX(-1).
    private func drawFootprint(ctx: inout GraphicsContext, at point: CGPoint,
                                angle: CGFloat, isLeft: Bool) {
        var transform = CGAffineTransform.identity
            .translatedBy(x: point.x, y: point.y)
            .rotated(by: angle)
        if !isLeft {
            transform = transform.scaledBy(x: -1, y: 1)
        }

        let fp = footprintPath().applying(transform)
        ctx.fill(fp, with: .color(Color.gloGold.opacity(0.8)))
    }

    /// Base footprint silhouette (origin-centered, toes point up/-Y, heel at +Y)
    private func footprintPath() -> Path {
        var fp = Path()
        let w: CGFloat = 6.5
        let heelW: CGFloat = 3.5
        let len: CGFloat = 18

        fp.move(to: CGPoint(x: -heelW, y: 2))
        fp.addQuadCurve(to: CGPoint(x: heelW, y: 2),
                        control: CGPoint(x: 0, y: -1))
        fp.addCurve(to: CGPoint(x: w, y: -len/2),
                    control1: CGPoint(x: heelW + 2, y: -2),
                    control2: CGPoint(x: w, y: -len/2 + 3))
        fp.addQuadCurve(to: CGPoint(x: -w, y: -len/2),
                        control: CGPoint(x: 0, y: -len/2 - 3))
        fp.addCurve(to: CGPoint(x: -heelW, y: 2),
                    control1: CGPoint(x: -w, y: -len/2 + 3),
                    control2: CGPoint(x: -(heelW + 2), y: -2))
        fp.closeSubpath()
        return fp
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
