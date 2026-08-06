import XCTest
import CoreData
@testable import GloWalk

final class PathProjectorTests: XCTestCase {

    var context: NSManagedObjectContext!

    override func setUp() {
        let container = NSPersistentContainer(name: "GloWalk")
        let desc = NSPersistentStoreDescription()
        desc.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [desc]
        container.loadPersistentStores { _, error in
            XCTAssertNil(error, "In-memory store should load")
        }
        context = container.viewContext
        // Reset the shared simplification tunables so tests are independent.
        PathProjector.simplificationFactor = 0.006
        PathProjector.simplificationMin = 1.5
    }

    // MARK: - Point Creation Helpers

    private func makePoint(lat: Double, lon: Double, light: Double = 0.5) -> PathPoint {
        let pt = PathPoint(context: context)
        pt.latitude = lat
        pt.longitude = lon
        pt.ambientLight = light
        pt.torchBrightness = light  // constellation coloring uses torch brightness
        pt.timestamp = Date()
        return pt
    }

    // MARK: - Projection

    func testProjectMapsLatLonToRect() {
        let points = [
            makePoint(lat: 39.9, lon: 116.4),  // Beijing
            makePoint(lat: 39.91, lon: 116.41),
        ]
        let area = CGRect(x: 0, y: 0, width: 300, height: 100)

        guard let projector = PathProjector(points: points, area: area) else {
            XCTFail("Should create projector with 2 points")
            return
        }

        let p0 = projector.project(points[0])
        let p1 = projector.project(points[1])

        // Second point is north-east of first point
        // In projected coords: Y decreases northward, X increases eastward
        XCTAssertLessThan(p1.y, p0.y, "North should map to smaller Y")
        XCTAssertGreaterThan(p1.x, p0.x, "East should map to larger X")

        // Points should be within the area bounds
        XCTAssertGreaterThanOrEqual(p0.x, area.minX - 1)
        XCTAssertLessThanOrEqual(p0.x, area.maxX + 1)
        XCTAssertGreaterThanOrEqual(p0.y, area.minY - 1)
        XCTAssertLessThanOrEqual(p0.y, area.maxY + 1)
    }

    func testSinglePointCreatesProjectorButNoSegments() {
        let points = [makePoint(lat: 39.9, lon: 116.4)]
        let area = CGRect(x: 0, y: 0, width: 300, height: 100)

        // Single point creates a valid projector (needed for start/end point access)
        let projector = PathProjector(points: points, area: area)
        XCTAssertNotNil(projector, "Single point should create a projector")
        XCTAssertNotNil(projector?.startPoint())
        XCTAssertNotNil(projector?.endPoint())
    }

    func testSinglePointSameLocation() {
        let points = [
            makePoint(lat: 39.9, lon: 116.4),
            makePoint(lat: 39.9, lon: 116.4),
        ]
        let area = CGRect(x: 0, y: 0, width: 300, height: 100)

        guard let projector = PathProjector(points: points, area: area) else {
            XCTFail("Should create projector")
            return
        }

        // Same location → points projected to same spot
        let p0 = projector.project(points[0])
        let p1 = projector.project(points[1])
        XCTAssertEqual(p0.x, p1.x, accuracy: 1)
        XCTAssertEqual(p0.y, p1.y, accuracy: 1)
    }

    // MARK: - Segment Iteration

    func testTwoPointsYieldsOneSegment() {
        let points = [
            makePoint(lat: 39.9, lon: 116.4, light: 0.3),
            makePoint(lat: 39.91, lon: 116.41, light: 0.7),
        ]
        let area = CGRect(x: 0, y: 0, width: 300, height: 100)

        guard let projector = PathProjector(points: points, area: area) else {
            XCTFail("Should create projector")
            return
        }

        var segmentCount = 0
        projector.forEachSegment { pt1, pt2, cp1, cp2, avgTorch in
            segmentCount += 1
            // Catmull-Rom control points for a 2-point path lie on the segment
            XCTAssertEqual(cp1.x, pt1.x + (pt2.x - pt1.x) / 6, accuracy: 0.5)
            XCTAssertEqual(cp1.y, pt1.y + (pt2.y - pt1.y) / 6, accuracy: 0.5)
            XCTAssertEqual(cp2.x, pt2.x - (pt2.x - pt1.x) / 6, accuracy: 0.5)
            XCTAssertEqual(cp2.y, pt2.y - (pt2.y - pt1.y) / 6, accuracy: 0.5)
            XCTAssertEqual(avgTorch, 0.5, accuracy: 0.01,
                           "Average torch brightness should be (0.3 + 0.7) / 2 = 0.5")
        }
        XCTAssertEqual(segmentCount, 1, "Two points should yield exactly one segment")
    }

    func testBezierCurveSegmentCount() {
        // A zig-zag, so every point genuinely shapes the path and survives
        // Douglas-Peucker → N points → N-1 segments (one Bézier per pair).
        // (Perfectly collinear points collapse to a single segment; that case
        // is covered by testCollinearRunSimplifiedToSingleSegment.)
        let three = [
            makePoint(lat: 39.900, lon: 116.400),
            makePoint(lat: 39.905, lon: 116.410),
            makePoint(lat: 39.900, lon: 116.420),
        ]
        let area = CGRect(x: 0, y: 0, width: 300, height: 100)
        var projector = PathProjector(points: three, area: area)!
        var count = 0
        projector.forEachSegment { _, _, _, _, _ in count += 1 }
        XCTAssertEqual(count, 2, "3 non-collinear points → 2 segments")

        // 4 points → 3 bezier segments
        let four = three + [makePoint(lat: 39.905, lon: 116.430)]
        projector = PathProjector(points: four, area: area)!
        count = 0
        projector.forEachSegment { _, _, _, _, _ in count += 1 }
        XCTAssertEqual(count, 3, "4 non-collinear points → 3 segments")
    }

    // MARK: - Start and End Points

    func testStartAndEndPoints() {
        let points = [
            makePoint(lat: 39.9, lon: 116.4),
            makePoint(lat: 39.91, lon: 116.41),
            makePoint(lat: 39.92, lon: 116.42),
        ]
        let area = CGRect(x: 0, y: 0, width: 300, height: 100)

        guard let projector = PathProjector(points: points, area: area) else {
            XCTFail("Should create projector")
            return
        }

        let start = projector.startPoint()
        let end = projector.endPoint()

        XCTAssertNotNil(start)
        XCTAssertNotNil(end)
        XCTAssertEqual(start, projector.project(points[0]))
        XCTAssertEqual(end, projector.project(points[2]))
    }

    // MARK: - Range Computation

    func testLatLonRangeUsesMinimumSpan() {
        // Two nearly identical points should still work
        let points = [
            makePoint(lat: 39.900001, lon: 116.400001),
            makePoint(lat: 39.900002, lon: 116.400002),
        ]
        let area = CGRect(x: 0, y: 0, width: 300, height: 100)

        guard let projector = PathProjector(points: points, area: area) else {
            XCTFail("Should create projector")
            return
        }

        // Should use the minimum range (0.00005) to avoid division by zero
        XCTAssertGreaterThan(projector.latRange, 0)
        XCTAssertGreaterThan(projector.lonRange, 0)
    }

    // MARK: - Douglas-Peucker Simplification

    func testCollinearRunSimplifiedToSingleSegment() {
        // Five perfectly collinear points: only the endpoints survive, and the
        // segment's torch becomes the mean of all five (0.1...0.5 → 0.3).
        let points = [
            makePoint(lat: 39.900, lon: 116.400, light: 0.1),
            makePoint(lat: 39.901, lon: 116.401, light: 0.2),
            makePoint(lat: 39.902, lon: 116.402, light: 0.3),
            makePoint(lat: 39.903, lon: 116.403, light: 0.4),
            makePoint(lat: 39.904, lon: 116.404, light: 0.5),
        ]
        let area = CGRect(x: 0, y: 0, width: 300, height: 100)

        guard let projector = PathProjector(points: points, area: area) else {
            XCTFail("Should create projector")
            return
        }

        var segments: [(CGPoint, CGPoint, Double)] = []
        projector.forEachSegment { pt1, pt2, _, _, avgTorch in
            segments.append((pt1, pt2, avgTorch))
        }
        XCTAssertEqual(segments.count, 1, "Collinear run should collapse to a single segment")
        XCTAssertEqual(segments[0].2, 0.3, accuracy: 0.001,
                       "Segment torch should be the mean of all five original points")
        XCTAssertEqual(segments[0].0, projector.project(points[0]), "Start anchor preserved")
        XCTAssertEqual(segments[0].1, projector.project(points[4]), "End anchor preserved")
    }

    func testSharpCornerKeptInSimplification() {
        // L-shaped path: the corner stays an anchor, the straight legs collapse.
        let points = [
            makePoint(lat: 39.900, lon: 116.400),
            makePoint(lat: 39.900, lon: 116.410),
            makePoint(lat: 39.900, lon: 116.420),
            makePoint(lat: 39.910, lon: 116.420),
            makePoint(lat: 39.920, lon: 116.420),
        ]
        let area = CGRect(x: 0, y: 0, width: 300, height: 100)

        guard let projector = PathProjector(points: points, area: area) else {
            XCTFail("Should create projector")
            return
        }

        var firstAnchor: CGPoint?
        var segmentCount = 0
        projector.forEachSegment { pt1, _, _, _, _ in
            if firstAnchor == nil { firstAnchor = pt1 }
            segmentCount += 1
        }
        XCTAssertEqual(segmentCount, 2, "Corner should split the path into two segments")
        XCTAssertEqual(firstAnchor, projector.project(points[0]), "Start anchor preserved")
    }

    func testSimplificationMergesTorchFromDroppedPoints() {
        // Bright middle run with dark endpoints: the merged segment must carry
        // the bright middle, not just the average of the two endpoints.
        let points = [
            makePoint(lat: 39.900, lon: 116.400, light: 0.1),
            makePoint(lat: 39.901, lon: 116.401, light: 0.9),
            makePoint(lat: 39.902, lon: 116.402, light: 0.9),
            makePoint(lat: 39.903, lon: 116.403, light: 0.9),
            makePoint(lat: 39.904, lon: 116.404, light: 0.1),
        ]
        let area = CGRect(x: 0, y: 0, width: 300, height: 100)

        guard let projector = PathProjector(points: points, area: area) else {
            XCTFail("Should create projector")
            return
        }

        var avgTorch: Double = -1
        projector.forEachSegment { _, _, _, _, t in avgTorch = t }
        XCTAssertEqual(avgTorch, 0.58, accuracy: 0.001,
                       "Torch data from removed points must be merged, not lost")
    }
}
