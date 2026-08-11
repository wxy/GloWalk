import XCTest
import CoreData
import HealthKit
import CoreLocation
@testable import GloWalk

@MainActor
final class HealthSyncServiceTests: XCTestCase {
    private var context: NSManagedObjectContext!

    override func setUp() {
        super.setUp()
        context = PersistenceController(inMemory: true).container.viewContext
    }

    private func makeSession(steps: Int64 = 100, distance: Double = 80,
                             state: String? = nil) -> WalkSession {
        let session = WalkSession(context: context)
        session.id = UUID()
        session.startTime = Date(timeIntervalSinceReferenceDate: 1000)
        session.endTime = Date(timeIntervalSinceReferenceDate: 1500)
        session.totalSteps = steps
        session.totalDistance = distance
        session.healthSyncState = state
        try? context.save()
        return session
    }

    func testAuthorizationFlowRequestsThenWrites() async {
        let mock = MockHealthStore(status: .notDetermined)
        mock.statusAfterRequest = .sharingAuthorized
        let service = HealthSyncService(store: mock, context: context)
        let session = makeSession()

        await service.sync(session: session)

        XCTAssertEqual(mock.requestCallCount, 1)
        XCTAssertEqual(mock.savedWorkout?.workoutActivityType, .walking)
        XCTAssertEqual(mock.savedSamples.count, 2)
        XCTAssertEqual(session.healthSyncState, HealthSyncState.synced.rawValue)
    }

    func testDeniedAfterRequestSkips() async {
        let mock = MockHealthStore(status: .notDetermined)
        mock.statusAfterRequest = .sharingDenied
        let service = HealthSyncService(store: mock, context: context)
        let session = makeSession()

        await service.sync(session: session)

        XCTAssertEqual(mock.requestCallCount, 1)
        XCTAssertNil(mock.savedWorkout)
        XCTAssertEqual(session.healthSyncState, HealthSyncState.skipped.rawValue)
    }

    func testAlreadyDeniedSkipsWithoutRequest() async {
        let mock = MockHealthStore(status: .sharingDenied)
        let service = HealthSyncService(store: mock, context: context)
        let session = makeSession()

        await service.sync(session: session)

        XCTAssertEqual(mock.requestCallCount, 0)
        XCTAssertEqual(session.healthSyncState, HealthSyncState.skipped.rawValue)
    }

    func testUnavailableStoreDoesNothing() async {
        let mock = MockHealthStore(status: .sharingAuthorized)
        mock.isAvailable = false
        let service = HealthSyncService(store: mock, context: context)
        let session = makeSession()

        await service.sync(session: session)

        XCTAssertNil(mock.savedWorkout)
        XCTAssertNil(session.healthSyncState)
    }

    func testSaveFailureMarksFailed() async {
        let mock = MockHealthStore(status: .sharingAuthorized)
        mock.saveError = HealthStoreError.routeFinishFailed
        let service = HealthSyncService(store: mock, context: context)
        let session = makeSession()

        await service.sync(session: session)

        XCTAssertEqual(session.healthSyncState, HealthSyncState.failed.rawValue)
    }

    func testRetryOnlyPendingAndFailed() async {
        let mock = MockHealthStore(status: .sharingAuthorized)
        let service = HealthSyncService(store: mock, context: context)
        let pending = makeSession(state: HealthSyncState.pending.rawValue)
        let failed = makeSession(state: HealthSyncState.failed.rawValue)
        let skipped = makeSession(state: HealthSyncState.skipped.rawValue)
        let old = makeSession(state: nil)   // 授权前的老记录，永不补录

        await service.retryPending()

        XCTAssertEqual(pending.healthSyncState, HealthSyncState.synced.rawValue)
        XCTAssertEqual(failed.healthSyncState, HealthSyncState.synced.rawValue)
        XCTAssertEqual(skipped.healthSyncState, HealthSyncState.skipped.rawValue)
        XCTAssertNil(old.healthSyncState)
        XCTAssertEqual(mock.savedWorkouts.count, 2)
    }

    func testRetryMarksSkippedWhenRevoked() async {
        let mock = MockHealthStore(status: .sharingDenied)
        let service = HealthSyncService(store: mock, context: context)
        let failed = makeSession(state: HealthSyncState.failed.rawValue)

        await service.retryPending()

        XCTAssertEqual(failed.healthSyncState, HealthSyncState.skipped.rawValue)
        XCTAssertNil(mock.savedWorkout)
    }
}

@MainActor
private final class MockHealthStore: HealthStoreProtocol {
    var isAvailable: Bool
    var status: HKAuthorizationStatus
    var statusAfterRequest: HKAuthorizationStatus?
    var requestError: Error?
    var saveError: Error?
    var requestCallCount = 0
    private(set) var savedWorkout: HKWorkout?
    private(set) var savedWorkouts: [HKWorkout] = []
    private(set) var savedSamples: [HKQuantitySample] = []

    init(status: HKAuthorizationStatus, isAvailable: Bool = true) {
        self.status = status
        self.isAvailable = isAvailable
    }

    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus { status }

    func requestAuthorization(toShare: Set<HKSampleType>, read: Set<HKObjectType>) async throws {
        requestCallCount += 1
        if let statusAfterRequest { status = statusAfterRequest }
        if let requestError { throw requestError }
    }

    func save(workout: HKWorkout, samples: [HKQuantitySample],
              routeLocations: [CLLocation]) async throws {
        if let saveError { throw saveError }
        savedWorkout = workout
        savedWorkouts.append(workout)
        savedSamples = samples
    }
}
