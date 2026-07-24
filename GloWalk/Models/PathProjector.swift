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

    /// Emit one smooth cubic-Bézier segment per consecutive pair of points,
    /// forming a single continuous curve that passes through every point.
    ///
    /// Uses the Catmull-Rom → Bézier conversion: for a segment P1→P2 with
    /// neighbours P0 and P3 the control points are
    ///   C1 = P1 + (P2 − P0) / 6,  C2 = P2 − (P3 − P1) / 6.
    /// Endpoints are clamped (P0 = P1 at the start, P3 = P2 at the end), so the
    /// curve is C1-continuous — no kinks, no gaps — and its two tips land
    /// exactly on the first and last points where the footprint markers sit.
    ///
    /// `drawSegment` receives: start, end, control1, control2, avgLight (0-1).
    func forEachSegment(_ drawSegment: (CGPoint, CGPoint, CGPoint, CGPoint, Double) -> Void) {
        guard points.count >= 2 else { return }

        // Project once; drop points that land on the same spot (GPS jitter in
        // place) so they don't introduce zero-length wiggles in the curve.
        var pts: [CGPoint] = []
        var lights: [Double] = []
        for p in points {
            let sp = project(p)
            if let last = pts.last, hypot(sp.x - last.x, sp.y - last.y) < 0.5 { continue }
            pts.append(sp)
            lights.append(p.ambientLight)
        }
        guard pts.count >= 2 else { return }

        for i in 0..<(pts.count - 1) {
            let p0 = pts[max(i - 1, 0)]
            let p1 = pts[i]
            let p2 = pts[i + 1]
            let p3 = pts[min(i + 2, pts.count - 1)]

            let cp1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6.0,
                              y: p1.y + (p2.y - p0.y) / 6.0)
            let cp2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6.0,
                              y: p2.y - (p3.y - p1.y) / 6.0)

            let avgLight = (lights[i] + lights[i + 1]) / 2.0
            drawSegment(p1, p2, cp1, cp2, avgLight)
        }
    }

    func startPoint() -> CGPoint? {
        points.first.map(project)
    }
    func endPoint() -> CGPoint? {
        points.last.map(project)
    }
}
