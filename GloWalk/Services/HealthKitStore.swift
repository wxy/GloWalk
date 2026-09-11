import HealthKit
import CoreLocation

protocol HealthStoreProtocol {
    var isAvailable: Bool { get }
    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus
    func requestAuthorization(toShare: Set<HKSampleType>, read: Set<HKObjectType>) async throws
    func save(workout: HKWorkout, samples: [HKQuantitySample], routeLocations: [CLLocation]) async throws
    /// Delete every workout this app wrote for `sessionID` (the metadata key
    /// GloWalkSessionID) — used when the user deletes a walk from history.
    func deleteWorkouts(sessionID: String) async throws
}

enum HealthStoreError: Error {
    case routeFinishFailed
    case deleteFailed
}

final class HealthKitStore: HealthStoreProtocol {
    static let writeTypes: Set<HKSampleType> = [
        HKQuantityType.quantityType(forIdentifier: .stepCount)!,
        HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!,
        HKObjectType.workoutType() as HKSampleType,
    ]

    private let healthStore = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus {
        healthStore.authorizationStatus(for: type)
    }

    func requestAuthorization(toShare typesToShare: Set<HKSampleType>,
                              read typesToRead: Set<HKObjectType>) async throws {
        try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
    }

    func save(workout: HKWorkout, samples: [HKQuantitySample],
              routeLocations: [CLLocation]) async throws {
        // Stable per-session sync metadata makes retries idempotent.
        // Route coordinates deliberately never leave the local store.
        try await healthStore.save([workout] + samples)
    }

    func deleteWorkouts(sessionID: String) async throws {
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HealthWorkoutFactory.sessionIDMetadataKey,
            operatorType: .equalTo,
            value: sessionID)
        let samples: [HKSample] = try await withCheckedThrowingContinuation { cont in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil) { _, results, error in
                    if let error {
                        cont.resume(throwing: error)
                    } else {
                        cont.resume(returning: results ?? [])
                    }
                }
            healthStore.execute(query)
        }
        guard !samples.isEmpty else { return }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            healthStore.delete(samples) { success, error in
                if success {
                    cont.resume()
                } else {
                    cont.resume(throwing: error ?? HealthStoreError.deleteFailed)
                }
            }
        }
    }
}
