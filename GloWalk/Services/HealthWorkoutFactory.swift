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
            duration: end.timeIntervalSince(start),
            totalEnergyBurned: nil,
            totalDistance: distance > 0 ? HKQuantity(unit: .meter(), doubleValue: distance) : nil,
            metadata: [sessionIDMetadataKey: session.id?.uuidString ?? UUID().uuidString]
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
                start: start, end: end))
        }
        if session.totalDistance > 0 {
            result.append(HKQuantitySample(
                type: HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!,
                quantity: HKQuantity(unit: .meter(), doubleValue: session.totalDistance),
                start: start, end: end))
        }
        return result
    }

    static func routeLocations(session: WalkSession) -> [CLLocation] {
        let points = session.pathPointsArray
            .filter { $0.latitude != 0 || $0.longitude != 0 }
            .sorted { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) }
        guard points.count >= 2 else { return [] }
        return points.map { point in
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: point.latitude,
                                                   longitude: point.longitude),
                altitude: 0,
                horizontalAccuracy: 10,
                verticalAccuracy: -1,
                course: -1,
                speed: -1,
                timestamp: point.timestamp ?? Date())
        }
    }
}
