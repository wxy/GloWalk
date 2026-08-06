import SwiftUI

struct ConstellationPathView: View {
    let points: [PathPoint]
    let isActive: Bool
    /// Steps taken so far — the front footprint alternates left/right on each
    /// step, so the marker reads as a walking gait instead of a static foot.
    var stepCount: Int = 0

    var body: some View {
        Canvas { ctx, size in
            // Small margin so the footprint markers/glow don't clip at the
            // edges; the projector centres the curve within `area`.
            let inset: CGFloat = 14
            let area = CGRect(x: inset, y: inset,
                              width: size.width - inset * 2,
                              height: size.height - inset * 2)
            guard let projector = PathProjector(points: points, area: area),
                  points.count >= 2 else { return }

            // Draw the smooth constellation curve — one Bézier per segment,
            // joined C1-continuously so the whole path reads as a single line.
            projector.forEachSegment { pt1, pt2, cp1, cp2, avgTorch in
                // Brighter torch (flashlight) → brighter, slightly thicker line.
                // Deliberately thin — a constellation hairline, not a stroke —
                // and the poster multiplies the same formula by the device scale
                // so both surfaces read with identical visual weight.
                let alpha = 0.3 + avgTorch * 0.5
                let width = 0.6 + avgTorch * 1.0

                var path = Path()
                path.move(to: pt1)
                path.addCurve(to: pt2, control1: cp1, control2: cp2)

                ctx.stroke(path,
                    with: .color(Color.gloGold.opacity(alpha)),
                    style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            }

            // Start — 👣 centered on the first point so it sits on the curve tip
            if let sp = projector.startPoint() {
                ctx.draw(Text("👣").font(.system(size: 10)), at: sp)
            }

            // Footprint trail — the front foot flips between left and right as
            // steps land, prints behind the walker fade out, and each is
            // rotated so its toes point along the local path direction. Prints
            // sit on the curve's own anchor points (the ones the Bézier passes
            // through), so the front print is always exactly on the curve's
            // end tip and the ones behind follow the redrawn path — not on raw
            // GPS points that drift off the line. Real step spacing is
            // sub-pixel at HUD scale, so consecutive prints keep a small gap
            // and the older ones trail behind fainter.
            let anchors = projector.anchors()
            var trail: [CGPoint] = []
            var lastPrint: CGPoint?
            for p in anchors.reversed() {
                if let l = lastPrint, hypot(p.x - l.x, p.y - l.y) < 4 { continue }
                trail.append(p)
                lastPrint = p
                if trail.count >= 4 { break }
            }
            trail.reverse()
            let frontIsLeft = stepCount.isMultiple(of: 2)
            let alphas: [CGFloat] = [1.0, 0.6, 0.35, 0.18]
            for (i, pos) in trail.enumerated() {
                let fromFront = trail.count - 1 - i
                let isLeft = frontIsLeft != (fromFront % 2 == 1)
                // Travel direction through this print: toward the next (newer)
                // one; the front print uses the last two prints' direction.
                let angle: CGFloat
                if i + 1 < trail.count {
                    angle = atan2(trail[i + 1].y - pos.y, trail[i + 1].x - pos.x)
                } else if trail.count > 1 {
                    angle = atan2(pos.y - trail[i - 1].y, pos.x - trail[i - 1].x)
                } else {
                    angle = 0
                }
                drawFootprint(ctx: &ctx, at: pos, angle: angle,
                              isLeft: isLeft, alpha: alphas[min(fromFront, 3)])
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

    // MARK: - Footprint marker

    /// The affine transform that draws a footprint glyph centred on `pos`,
    /// rotated so its toes face `angle` (radians, 0 = right in y-down screen
    /// space), and mirrored to the left foot when `isLeft`. Internal so the
    /// transform math is unit-testable.
    ///
    /// The chained mutators PREPEND each new transform, so the glyph is first
    /// rotated (and, for the left foot, mirrored) in its own local frame and
    /// then translated to `pos` — the reverse order would swing the print
    /// around the canvas origin and throw it off-screen.
    static func footprintTransform(at pos: CGPoint, angle: CGFloat,
                                   isLeft: Bool,
                                   toeAngle: CGFloat = -0.7) -> CGAffineTransform {
        if isLeft {
            // R(−toe)·S(1,−1)·R(angle)·T(pos): mirror across the foot's own
            // toe-heel axis (the x-axis once the glyph is rotated flat to
            // toeAngle), then rotate so the toes point along `angle`, then
            // move to `pos`. Mirroring across that axis flips the big-toe side
            // without flipping the toe direction — a plain horizontal mirror
            // would make the left foot point the opposite way to the right.
            return CGAffineTransform.identity
                .translatedBy(x: pos.x, y: pos.y)
                .rotated(by: angle)
                .scaledBy(x: 1, y: -1)
                .rotated(by: -toeAngle)
        } else {
            return CGAffineTransform.identity
                .translatedBy(x: pos.x, y: pos.y)
                .rotated(by: angle - toeAngle)
        }
    }

    /// Draw one footprint at `pos`, rotated so its toes face `angle`, and
    /// faded by `alpha` so older prints trail behind the walker. The 🦶 glyph
    /// ships one foot; its mirrored twin is the other foot.
    private func drawFootprint(ctx: inout GraphicsContext, at pos: CGPoint,
                               angle: CGFloat, isLeft: Bool, alpha: CGFloat) {
        // Glow aura — same 12pt as the poster's 36px at 3×, scaled with the
        // print's own alpha so the trail fades as one unit.
        let glowRect = CGRect(x: pos.x - 6, y: pos.y - 6, width: 12, height: 12)
        ctx.fill(Path(ellipseIn: glowRect),
                 with: .color(Color.gloGold.opacity(0.18 * alpha)))

        // The 🦶 glyph's toes point up-right by default (≈ −0.7 rad in y-down
        // screen space); rotating the draw so they align with `angle` makes the
        // foot face where the user is heading. Tweaking the constant rotates
        // every print by the same amount — tune it against the glyph revision.
        let transform = Self.footprintTransform(at: pos, angle: angle, isLeft: isLeft)

        let foot = Text("🦶").font(.system(size: 10))
        ctx.drawLayer { layer in
            layer.opacity = Double(alpha)
            layer.transform = transform
            layer.draw(foot, at: .zero)
        }
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
