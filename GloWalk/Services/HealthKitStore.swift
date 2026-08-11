import HealthKit
import CoreLocation

protocol HealthStoreProtocol {
    var isAvailable: Bool { get }
    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus
    func requestAuthorization(toShare: Set<HKSampleType>, read: Set<HKObjectType>) async throws
    func save(workout: HKWorkout, samples: [HKQuantitySample], routeLocations: [CLLocation]) async throws
}

enum HealthStoreError: Error {
    case routeAddFailed
    case routeFinishFailed
}

final class HealthKitStore: HealthStoreProtocol {
    static let writeTypes: Set<HKSampleType> = [
        HKQuantityType.quantityType(forIdentifier: .stepCount)!,
        HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!,
        HKObjectType.workoutType() as HKSampleType,
        HKSeriesType.workoutRoute() as HKSampleType,
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
        // workout 必须先保存，finishRoute 才能把路线关联到它。
        try await healthStore.save([workout] + samples)
        // iOS 26 SDK 的 HKWorkoutRouteBuilder 改为 healthStore/device 初始化器；
        // 用 #available 保护，低版本系统只保存训练与样本、省略路线。
        if #available(iOS 18.0, *), routeLocations.count >= 2 {
            let builder = HKWorkoutRouteBuilder(healthStore: healthStore, device: nil)
            try await builder.insertRouteData(routeLocations)
            let route = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<HKWorkoutRoute, Error>) in
                builder.finishRoute(with: workout,
                                    metadata: workout.metadata) { route, error in
                    if let route { cont.resume(returning: route) } else {
                        cont.resume(throwing: error ?? HealthStoreError.routeFinishFailed)
                    }
                }
            }
            _ = route
        }
    }
}
