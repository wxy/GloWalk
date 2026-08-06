import CoreLocation

/// Shared GPS→screen coordinate projector used by both HUD and poster.
struct PathProjector {
    let points: [PathPoint]
    let area: CGRect

    private let minLat: Double
    private let maxLat: Double
    private let minLon: Double
    private let maxLon: Double

    init?(points: [PathPoint], area: CGRect) {
        guard points.count >= 1 else { return nil }
        self.points = points
        self.area = area
        let lats = points.map(\.latitude)
        let lons = points.map(\.longitude)
        guard let mnLa = lats.min(), let mxLa = lats.max(),
              let mnLo = lons.min(), let mxLo = lons.max() else { return nil }
        minLat = mnLa; maxLat = mxLa
        minLon = mnLo; maxLon = mxLo
    }

    var latRange: Double { max(maxLat - minLat, 0.00005) }
    var lonRange: Double { max(maxLon - minLon, 0.00005) }

    /// Longitude→latitude distance correction at this location: 1° of longitude
    /// spans cos(latitude) as much ground as 1° of latitude.
    private var lonScale: Double {
        max(cos((minLat + maxLat) / 2 * .pi / 180), 0.01)
    }

    // MARK: - Simplification tunables

    /// Douglas-Peucker tolerance as a fraction of the drawing area's shortest
    /// side. A projected point is only kept when it deviates more than this
    /// from the line between its neighbouring anchors — dense GPS/step logging
    /// (~5 m per point, ~0.7 m while dead-reckoning) collapses into a handful
    /// of anchors per block, which kills the GPS-jitter wobble and cuts the
    /// per-frame Bézier count in the live HUD.
    static var simplificationFactor: CGFloat = 0.006
    /// Absolute floor (projected units) so a tiny drawing area never
    /// over-simplifies an already-short path down to a straight line.
    static var simplificationMin: CGFloat = 1.5

    /// A path that has been simplified: the anchor points the curve passes
    /// through, plus one brightness value per segment (the mean torch of every
    /// original point that segment now represents — merging data, not losing
    /// it, when points get removed).
    private struct SimplifiedPath {
        let points: [CGPoint]
        let segTorch: [Double]
    }

    /// Project a point using a single uniform scale so the path keeps its true
    /// geographic proportions, then centre it inside `area`. This makes the
    /// shape identical regardless of the drawing area's aspect ratio (HUD vs
    /// poster) — only the overall size changes, never the shape.
    func project(_ p: PathPoint) -> CGPoint {
        let geoWidth = lonRange * lonScale
        let geoHeight = latRange
        let scale = min(area.width / geoWidth, area.height / geoHeight)
        let drawnWidth = geoWidth * scale
        let drawnHeight = geoHeight * scale
        let originX = area.origin.x + (area.width - drawnWidth) / 2
        let originY = area.origin.y + (area.height - drawnHeight) / 2
        return CGPoint(
            x: originX + CGFloat((p.longitude - minLon) * lonScale) * scale,
            y: originY + CGFloat(maxLat - p.latitude) * scale  // north = up
        )
    }

    /// Emit one smooth cubic-Bézier segment per consecutive pair of *anchor*
    /// points (the path after Douglas-Peucker simplification), forming a single
    /// continuous curve that passes through every anchor.
    ///
    /// Uses the Catmull-Rom → Bézier conversion: for a segment P1→P2 with
    /// neighbours P0 and P3 the control points are
    ///   C1 = P1 + (P2 − P0) / 6,  C2 = P2 − (P3 − P1) / 6.
    /// Endpoints are clamped (P0 = P1 at the start, P3 = P2 at the end), so the
    /// curve is C1-continuous — no kinks, no gaps — and its two tips land
    /// exactly on the first and last points where the footprint markers sit.
    ///
    /// `drawSegment` receives: start, end, control1, control2, avgTorch (0-1)
    /// — the mean torch (flashlight) brightness of every original point the
    /// segment represents after simplification.
    func forEachSegment(_ drawSegment: (CGPoint, CGPoint, CGPoint, CGPoint, Double) -> Void) {
        guard points.count >= 2 else { return }

        // Project once; drop points that land on the same spot (GPS jitter in
        // place) so they don't introduce zero-length wiggles in the curve.
        var pts: [CGPoint] = []
        var torch: [Double] = []
        for p in points {
            let sp = project(p)
            if let last = pts.last, hypot(sp.x - last.x, sp.y - last.y) < 0.5 { continue }
            pts.append(sp)
            torch.append(p.torchBrightness)
        }
        guard pts.count >= 2 else { return }

        // Simplify: keep only the anchors that actually shape the path, and
        // re-mean the torch over each removed run so the constellation colour
        // still tracks the flashlight along the whole walk. This is the step
        // that removes the "unexpected kinks" — a GPS or dead-reckoning wobble
        // point is exactly what Douglas-Peucker drops, so the Bézier curve
        // glides over a clean skeleton instead of piercing every jitter point.
        let epsilon = max(Self.simplificationMin,
                          min(area.width, area.height) * Self.simplificationFactor)
        let simplified = epsilon > 0 ? simplify(pts: pts, torch: torch, epsilon: epsilon)
                                     : SimplifiedPath(points: pts,
                                                      segTorch: segmentTorchMeans(pts: pts, torch: torch, keptIdx: Array(pts.indices)))
        let aPts = simplified.points
        let aSegTorch = simplified.segTorch
        guard aPts.count >= 2 else { return }

        for i in 0..<(aPts.count - 1) {
            let p0 = aPts[max(i - 1, 0)]
            let p1 = aPts[i]
            let p2 = aPts[i + 1]
            let p3 = aPts[min(i + 2, aPts.count - 1)]

            let cp1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6.0,
                              y: p1.y + (p2.y - p0.y) / 6.0)
            let cp2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6.0,
                              y: p2.y - (p3.y - p1.y) / 6.0)

            drawSegment(p1, p2, cp1, cp2, aSegTorch[i])
        }
    }

    // MARK: - Douglas-Peucker simplification

    /// Douglas-Peucker with torch merging. Returns the kept anchors and one
    /// per-segment brightness value: the mean torch of every original point the
    /// segment covers, so brightness data from removed points is merged into
    /// the surviving curve rather than dropped.
    private func simplify(pts: [CGPoint], torch: [Double], epsilon: CGFloat) -> SimplifiedPath {
        let kept = douglasPeuckerKeep(pts: pts, epsilon: epsilon)
        var keptIdx: [Int] = []
        for (i, isKept) in kept.enumerated() where isKept { keptIdx.append(i) }
        return SimplifiedPath(points: keptIdx.map { pts[$0] },
                              segTorch: segmentTorchMeans(pts: pts, torch: torch, keptIdx: keptIdx))
    }

    /// Mean torch over each segment `[keptIdx[k], keptIdx[k+1]]` of the
    /// original point array (inclusive). Always keeps the curve's first and
    /// last points, so the start/end footprint markers stay glued to the tips.
    private func segmentTorchMeans(pts: [CGPoint], torch: [Double], keptIdx: [Int]) -> [Double] {
        var means: [Double] = []
        means.reserveCapacity(max(keptIdx.count - 1, 0))
        for k in 0..<(keptIdx.count - 1) {
            let lo = keptIdx[k]
            let hi = keptIdx[k + 1]
            var sum = 0.0
            for i in lo...hi { sum += torch[i] }
            means.append(sum / Double(hi - lo + 1))
        }
        return means
    }

    /// Iterative Douglas-Peucker: mark which projected points survive. The
    /// first and last points always survive.
    private func douglasPeuckerKeep(pts: [CGPoint], epsilon: CGFloat) -> [Bool] {
        var kept = [Bool](repeating: false, count: pts.count)
        guard pts.count >= 2 else { return kept }
        kept[0] = true
        kept[pts.count - 1] = true
        var stack: [(Int, Int)] = [(0, pts.count - 1)]
        while let (start, end) = stack.popLast() {
            guard end - start >= 2 else { continue }
            var maxDist: CGFloat = 0
            var maxIdx = start
            for i in (start + 1)..<end {
                let d = perpendicularDistance(from: pts[i], a: pts[start], b: pts[end])
                if d > maxDist { maxDist = d; maxIdx = i }
            }
            if maxDist > epsilon {
                kept[maxIdx] = true
                stack.append((start, maxIdx))
                stack.append((maxIdx, end))
            }
        }
        return kept
    }

    /// Perpendicular distance from `p` to the infinite line through `a` and `b`.
    private func perpendicularDistance(from p: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        if lenSq == 0 { return hypot(p.x - a.x, p.y - a.y) }
        let t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    func startPoint() -> CGPoint? {
        points.first.map(project)
    }
    func endPoint() -> CGPoint? {
        points.last.map(project)
    }
}
