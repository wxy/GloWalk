import CoreData

@objc(PathPoint)
public class PathPoint: NSManagedObject {
    @NSManaged public var latitude: Double
    @NSManaged public var longitude: Double
    @NSManaged public var timestamp: Date?
    @NSManaged public var ambientLight: Double
    @NSManaged public var torchBrightness: Double
    @NSManaged public var session: WalkSession?

    var wrappedTimestamp: Date { timestamp ?? Date() }

    static func create(in context: NSManagedObjectContext,
                       lat: Double, lon: Double,
                       ambientLight: Double,
                       torchBrightness: Double,
                       session: WalkSession) -> PathPoint {
        let point = PathPoint(context: context)
        point.latitude = lat
        point.longitude = lon
        point.timestamp = Date()
        point.ambientLight = ambientLight
        point.torchBrightness = torchBrightness
        point.session = session
        return point
    }
}
