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

    func project(_ p: PathPoint) -> CGPoint {
        CGPoint(
            x: area.origin.x + CGFloat((p.longitude - minLon) / lonRange) * area.width,
            y: area.origin.y + CGFloat(1.0 - (p.latitude - minLat) / latRange) * area.height
        )
    }

    /// Draw cubic bezier segments colored by light level.
    /// `drawSegment` is called per segment with: start point, end point, control1, control2, avgLight (0-1)
    func forEachSegment(_ drawSegment: (CGPoint, CGPoint, CGPoint, CGPoint, Double) -> Void) {
        guard points.count >= 3 else {
            // Handle 2-point case: straight line
            if points.count == 2 {
                let p0 = project(points[0]), p1 = project(points[1])
                let avg = (points[0].ambientLight + points[1].ambientLight) / 2.0
                drawSegment(p0, p1, p0, p1, avg)
            }
            return
        }
        let tension: CGFloat = 0.25
        for i in 2..<points.count {
            let p0 = points[i-2], p1 = points[i-1], p2 = points[i]
            let pt0 = project(p0), pt1 = project(p1), pt2 = project(p2)
            let avgLight = (p1.ambientLight + p2.ambientLight) / 2.0

            let cp1 = CGPoint(x: pt1.x + (pt2.x - pt0.x) * tension,
                              y: pt1.y + (pt2.y - pt0.y) * tension)
            let cp2 = CGPoint(x: pt2.x + (pt1.x - pt2.x) * tension,
                              y: pt2.y + (pt1.y - pt2.y) * tension)
            drawSegment(pt1, pt2, cp1, cp2, avgLight)
        }
    }

    func startPoint() -> CGPoint? {
        points.first.map(project)
    }
    func endPoint() -> CGPoint? {
        points.last.map(project)
    }
}
