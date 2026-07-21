import CoreData

@objc(WalkSession)
public class WalkSession: NSManagedObject {
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
    @NSManaged public var pathPoints: Set<PathPoint>?

    var wrappedId: UUID { id ?? UUID() }
    var wrappedStartTime: Date { startTime ?? Date() }
    var wrappedMoonPhase: String { moonPhase ?? "unknown" }
    var wrappedEndType: String { endType ?? "interrupted" }

    var pathPointsArray: [PathPoint] {
        pathPoints?.sorted { ($0.timestamp ?? Date()) < ($1.timestamp ?? Date()) } ?? []
    }

    static func create(in context: NSManagedObjectContext,
                       moonPhase: String,
                       weatherCondition: String?) -> WalkSession {
        let session = WalkSession(context: context)
        session.id = UUID()
        session.startTime = Date()
        session.moonPhase = moonPhase
        session.weatherCondition = weatherCondition
        session.endType = "interrupted"
        return session
    }
}
