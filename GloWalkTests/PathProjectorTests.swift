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
    }

    // MARK: - Point Creation Helpers

    private func makePoint(lat: Double, lon: Double, light: Double = 0.5) -> PathPoint {
        let pt = PathPoint(context: context)
        pt.latitude = lat
        pt.longitude = lon
        pt.ambientLight = light
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
        projector.forEachSegment { pt1, pt2, cp1, cp2, avgLight in
            segmentCount += 1
            // Control points should equal endpoints for 2-point line segment
            XCTAssertEqual(cp1, pt1)
            XCTAssertEqual(cp2, pt2)
            XCTAssertEqual(avgLight, 0.5, accuracy: 0.01,
                           "Average light should be (0.3 + 0.7) / 2 = 0.5")
        }
        XCTAssertEqual(segmentCount, 1, "Two points should yield exactly one segment")
    }

    func testBezierCurveSegmentCount() {
        // 3 points → 1 bezier segment (p0 provides tangent for p1→p2 curve)
        let three = [
            makePoint(lat: 39.9, lon: 116.4),
            makePoint(lat: 39.91, lon: 116.41),
            makePoint(lat: 39.92, lon: 116.42),
        ]
        var area = CGRect(x: 0, y: 0, width: 300, height: 100)
        var projector = PathProjector(points: three, area: area)!
        var count = 0
        projector.forEachSegment { _, _, _, _, _ in count += 1 }
        XCTAssertEqual(count, 1, "3 points → 1 bezier segment")

        // 4 points → 2 bezier segments
        let four = three + [makePoint(lat: 39.93, lon: 116.43)]
        projector = PathProjector(points: four, area: area)!
        count = 0
        projector.forEachSegment { _, _, _, _, _ in count += 1 }
        XCTAssertEqual(count, 2, "4 points → 2 bezier segments")
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
}
