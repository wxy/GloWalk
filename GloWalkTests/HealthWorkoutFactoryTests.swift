import XCTest
import CoreData
import HealthKit
import CoreLocation
@testable import GloWalk

@MainActor
final class HealthWorkoutFactoryTests: XCTestCase {
    private func makeSession() -> (WalkSession, NSManagedObjectContext) {
        let ctx = PersistenceController(inMemory: true).container.viewContext
        let session = WalkSession(context: ctx)
        session.id = UUID()
        session.startTime = Date(timeIntervalSinceReferenceDate: 1000)
        session.endTime = Date(timeIntervalSinceReferenceDate: 1600)
        session.totalSteps = 1200
        session.totalDistance = 900
        _ = PathPoint.create(in: ctx, lat: 31.0, lon: 121.0,
                             ambientLight: 0.5, torchBrightness: 0.8, session: session)
        _ = PathPoint.create(in: ctx, lat: 31.01, lon: 121.01,
                             ambientLight: 0.5, torchBrightness: 0.8, session: session)
        try? ctx.save()
        return (session, ctx)
    }

    func testWorkoutPayload() {
        let (session, _) = makeSession()
        let workout = HealthWorkoutFactory.workout(session: session)
        XCTAssertEqual(workout.workoutActivityType, .walking)
        XCTAssertEqual(workout.startDate, session.startTime)
        XCTAssertEqual(workout.endDate, session.endTime)
        XCTAssertEqual(workout.duration, 600, accuracy: 0.001)
        XCTAssertEqual(workout.totalDistance?.doubleValue(for: .meter()) ?? 0, 900, accuracy: 0.001)
        XCTAssertEqual(workout.metadata?[HealthWorkoutFactory.sessionIDMetadataKey] as? String,
                       session.id?.uuidString)
    }

    func testSamplesOnlyWhenPositive() {
        let ctx = PersistenceController(inMemory: true).container.viewContext
        let session = WalkSession(context: ctx)
        session.id = UUID()
        session.startTime = Date(timeIntervalSinceReferenceDate: 1000)
        session.endTime = Date(timeIntervalSinceReferenceDate: 1600)
        session.totalSteps = 0
        session.totalDistance = 0
        try? ctx.save()

        let samples = HealthWorkoutFactory.samples(session: session)
        XCTAssertTrue(samples.isEmpty)
    }

    func testSamplesContent() {
        let (session, _) = makeSession()
        let samples = HealthWorkoutFactory.samples(session: session)
        XCTAssertEqual(samples.count, 2)
        let steps = samples.first { $0.quantityType == HKQuantityType.quantityType(forIdentifier: .stepCount) }
        let distance = samples.first { $0.quantityType == HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) }
        XCTAssertEqual(steps?.quantity.doubleValue(for: .count()) ?? 0, 1200, accuracy: 0.001)
        XCTAssertEqual(distance?.quantity.doubleValue(for: .meter()) ?? 0, 900, accuracy: 0.001)
    }

    func testRouteLocationsRequiresTwoPoints() {
        let ctx = PersistenceController(inMemory: true).container.viewContext
        let session = WalkSession(context: ctx)
        session.id = UUID()
        session.startTime = Date()
        _ = PathPoint.create(in: ctx, lat: 31.0, lon: 121.0,
                             ambientLight: 0.5, torchBrightness: 0.8, session: session)
        try? ctx.save()
        XCTAssertTrue(HealthWorkoutFactory.routeLocations(session: session).isEmpty)
    }

    func testRouteLocationsSortedAndFiltered() {
        let (session, _) = makeSession()
        let locations = HealthWorkoutFactory.routeLocations(session: session)
        XCTAssertEqual(locations.count, 2)
        XCTAssertEqual(locations[0].coordinate.latitude, 31.0, accuracy: 0.0001)
        XCTAssertEqual(locations[1].coordinate.longitude, 121.01, accuracy: 0.0001)
    }
}
