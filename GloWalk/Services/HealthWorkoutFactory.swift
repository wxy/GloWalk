import Foundation
import HealthKit
import CoreLocation
import CoreData

/// 由 WalkSession 构造 HealthKit 载荷的纯逻辑。不依赖 HKHealthStore，可离线单测。
enum HealthWorkoutFactory {
    static let sessionIDMetadataKey = "GloWalkSessionID"

    static func workout(session: WalkSession) -> HKWorkout {
        let start = session.startTime ?? Date()
        let end = session.endTime ?? start
        let distance = session.totalDistance
        return HKWorkout(
            activityType: .walking,
            start: start,
            end: end,
            duration: session.duration,
            totalEnergyBurned: nil,
            totalDistance: distance > 0 ? HKQuantity(unit: .meter(), doubleValue: distance) : nil,
            metadata: metadata(session: session, kind: "workout")
        )
    }

    static func samples(session: WalkSession) -> [HKQuantitySample] {
        let start = session.startTime ?? Date()
        let end = session.endTime ?? start
        var result: [HKQuantitySample] = []
        if session.totalSteps > 0 {
            result.append(HKQuantitySample(
                type: HKQuantityType.quantityType(forIdentifier: .stepCount)!,
                quantity: HKQuantity(unit: .count(), doubleValue: Double(session.totalSteps)),
                start: start, end: end, metadata: metadata(session: session, kind: "steps")))
        }
        if session.totalDistance > 0 {
            result.append(HKQuantitySample(
                type: HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!,
                quantity: HKQuantity(unit: .meter(), doubleValue: session.totalDistance),
                start: start, end: end, metadata: metadata(session: session, kind: "distance")))
        }
        return result
    }

    static func metadata(session: WalkSession, kind: String) -> [String: Any] {
        let id = session.id?.uuidString ?? session.objectID.uriRepresentation().absoluteString
        return [sessionIDMetadataKey: id,
                HKMetadataKeySyncIdentifier: "glowalk.\(id).\(kind)",
                HKMetadataKeySyncVersion: 1]
    }

    static func routeLocations(session: WalkSession) -> [CLLocation] {
        // Exact coordinates stay in the local store. Never export routes to Health.
        []
    }
}
