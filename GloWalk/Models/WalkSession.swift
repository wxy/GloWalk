import CoreData

@objc(WalkSession)
public class WalkSession: NSManagedObject, Identifiable {
    @NSManaged public var activeDuration: NSNumber?
    @NSManaged public var lastCheckpoint: Date?
    @NSManaged public var memoryTaglineKey: String?
    @NSManaged public var id: UUID?
    @NSManaged public var startTime: Date?
    @NSManaged public var endTime: Date?
    @NSManaged public var totalSteps: Int64
    @NSManaged public var totalDistance: Double
    @NSManaged public var avgLightLevel: Double
    @NSManaged public var moonPhase: String?
    @NSManaged public var weatherCondition: String?
    @NSManaged public var posterImageData: Data?
    @NSManaged public var endType: String?
    @NSManaged public var healthSyncState: String?
    @NSManaged public var pathPoints: Set<PathPoint>?

    var duration: TimeInterval {
        activeDuration?.doubleValue ?? max(0, (endTime ?? startTime ?? Date()).timeIntervalSince(wrappedStartTime))
    }

    var isCompleteRecord: Bool {
        totalSteps > 0 && totalDistance > 0 && pathPointsArray.count >= 2 && duration > 0
    }

    var wrappedStartTime: Date { startTime ?? Date() }
    var wrappedMoonPhase: String { moonPhase ?? "unknown" }

    var pathPointsArray: [PathPoint] {
        pathPoints?.sorted { ($0.timestamp ?? Date()) < ($1.timestamp ?? Date()) } ?? []
    }

    static func create(in context: NSManagedObjectContext,
                       moonPhase: String,
                       weatherCondition: String?) -> WalkSession {
        let session = WalkSession(entity: NSEntityDescription.entity(forEntityName: "WalkSession", in: context)!, insertInto: context)
        session.id = UUID()
        session.startTime = Date()
        session.moonPhase = moonPhase
        session.weatherCondition = weatherCondition
        session.endType = "interrupted"
        return session
    }
}
