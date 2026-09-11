import Foundation
import CoreData

@main
struct Verify {
    static var checks = 0
    static func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        precondition(condition(), name)
        checks += 1
    }

    static func main() throws {
        let resource = Bundle.main.resourceURL!.appendingPathComponent("GloWalk.momd")
        for name in ["GloWalk", "GloWalk 2"] {
            let oldModel = NSManagedObjectModel(contentsOf: resource.appendingPathComponent(name + ".mom"))!
            let newModel = NSManagedObjectModel(contentsOf: resource.appendingPathComponent("GloWalk 3.mom"))!
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
            defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
            let old = NSPersistentStoreCoordinator(managedObjectModel: oldModel)
            try old.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url)
            let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
            context.persistentStoreCoordinator = old
            let s = NSManagedObject(entity: oldModel.entitiesByName["WalkSession"]!, insertInto: context)
            let id = UUID()
            s.setValue(id, forKey: "id")
            s.setValue(Date(timeIntervalSince1970: 1000), forKey: "startTime")
            s.setValue(Date(timeIntervalSince1970: 1600), forKey: "endTime")
            s.setValue(120, forKey: "totalSteps")
            s.setValue(84.0, forKey: "totalDistance")
            let point = NSManagedObject(entity: oldModel.entitiesByName["PathPoint"]!, insertInto: context)
            point.setValue(30.0, forKey: "latitude")
            point.setValue(120.0, forKey: "longitude")
            point.setValue(s, forKey: "session")
            try context.save()
            context.reset()
            for store in old.persistentStores { try old.remove(store) }
            let migrated = NSPersistentStoreCoordinator(managedObjectModel: newModel)
            try migrated.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url,
                options: [NSMigratePersistentStoresAutomaticallyOption: true, NSInferMappingModelAutomaticallyOption: true])
            let newContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
            newContext.persistentStoreCoordinator = migrated
            let records = try newContext.fetch(NSFetchRequest<WalkSession>(entityName: "WalkSession"))
            check(records.count == 1, "migration count")
            let saved = records[0]
            check(saved.id == id, "migration identity")
            check(saved.totalSteps == 120 && saved.totalDistance == 84, "migration stats")
            check(saved.activeDuration == nil && saved.duration == 600, "legacy duration")
            check(saved.memoryTaglineKey == nil, "legacy memory phrase")
            check(saved.pathPointsArray.count == 1 && saved.pathPointsArray[0].segmentID == 0, "legacy path")
            newContext.reset()
            for store in migrated.persistentStores { try migrated.remove(store) }
            print("PASS: \(name) -> version 3")
        }
        var clock = WalkClock()
        let start = Date(timeIntervalSince1970: 1000)
        clock.resume(at: start)
        clock.pause(at: start.addingTimeInterval(60))
        clock.pause(at: start.addingTimeInterval(90))
        check(clock.elapsed(at: start.addingTimeInterval(300)) == 60, "paused clock")
        clock.resume(at: start.addingTimeInterval(300))
        check(clock.elapsed(at: start.addingTimeInterval(330)) == 90, "resumed clock")
        let points: [PathProjector.Point] = [
            .init(latitude: 30, longitude: 120, torchBrightness: 0.2, segmentID: 0),
            .init(latitude: 30.001, longitude: 120, torchBrightness: 0.2, segmentID: 0),
            .init(latitude: 31, longitude: 121, torchBrightness: 0.8, segmentID: 1),
            .init(latitude: 31.001, longitude: 121, torchBrightness: 0.8, segmentID: 1)]
        let projector = PathProjector(points: points, area: CGRect(x: 0, y: 0, width: 10000, height: 10000))!
        var segments = 0
        projector.forEachSegment { _, _, _, _, _ in segments += 1 }
        check(segments == 2, "no bridge across pause")

        func memorySample(_ latitude: Double, _ longitude: Double,
                          light: Double = 0.5, segment: Int64 = 0) -> NightMemoryProfile.Sample {
            .init(latitude: latitude, longitude: longitude,
                  torchBrightness: light, segmentID: segment)
        }
        let straight = [memorySample(30, 120), memorySample(30.001, 120),
                        memorySample(30.002, 120)]
        func memoryProfile(duration: TimeInterval = 60, distance: Double = 50,
                           moon: String = "new_moon", weather: String? = nil,
                           samples: [NightMemoryProfile.Sample]) -> NightMemoryProfile {
            .init(duration: duration, distance: distance, moonPhase: moon,
                  weatherCondition: weather, samples: samples)
        }
        check(memoryProfile(weather: "rain", samples: straight).theme == .rain,
              "rain memory")
        check(memoryProfile(samples: [memorySample(30, 120, segment: 0),
                                      memorySample(30.001, 120, segment: 1)]).theme == .resumed,
              "resumed memory")
        check(memoryProfile(samples: [memorySample(30, 120, light: 0.1),
                                      memorySample(30.001, 120, light: 0.5),
                                      memorySample(30.002, 120, light: 0.9)]).theme == .changingLight,
              "changing-light memory")
        let winding = [memorySample(30, 120), memorySample(30.001, 120),
                       memorySample(30.001, 120.001), memorySample(30.002, 120.001)]
        check(memoryProfile(samples: winding).theme == .winding, "winding memory")
        check(memoryProfile(duration: 1_500, distance: 1_700,
                            samples: straight).theme == .longWalk, "long memory")
        check(memoryProfile(moon: "full_moon", samples: straight).theme == .moonlit,
              "moonlit memory")
        check(memoryProfile(samples: straight).theme == .quiet, "quiet memory")

        let memoryBaseKeys = ["tagline.rain", "tagline.resumed", "tagline.streetlight",
                              "tagline.winding", "tagline.adaptation", "tagline.moon",
                              "tagline.quiet"]
        for baseKey in memoryBaseKeys {
            let variants = Tagline.nightMemoryPool.filter {
                $0.key == baseKey || $0.key.hasPrefix(baseKey + ".")
            }
            check(variants.count == 3, "three variants for \(baseKey)")
            let selected = Set((0..<12).map {
                Tagline.nightMemory(key: baseKey, seed: UInt64($0)).key
            })
            check(selected.count == 3, "variant selection for \(baseKey)")
            check(Tagline.nightMemory(key: baseKey, seed: 42).key
                    == Tagline.nightMemory(key: baseKey, seed: 42).key,
                  "stable variant selection for \(baseKey)")
            let first = Tagline.nightMemory(key: baseKey, seed: 42)
            let second = Tagline.nightMemory(key: baseKey, seed: 42,
                                             excluding: [first.key])
            let third = Tagline.nightMemory(key: baseKey, seed: 42,
                                            excluding: [first.key, second.key])
            check(Set([first.key, second.key, third.key]).count == 3,
                  "unseen variants before repeats for \(baseKey)")
            let repeated = Tagline.nightMemory(
                key: baseKey, seed: 42, excluding: Set(variants.map(\.key)))
            check(variants.contains { $0.key == repeated.key },
                "variants repeat after theme completion for \(baseKey)")
        }
        check(Tagline.savedNightMemory(key: "tagline.quiet")?.key == "tagline.quiet",
              "legacy phrase key remains exact")
        check(Tagline.savedNightMemory(key: "tagline.quiet.missing") == nil,
              "unknown saved phrase key")
        print("PASS: \(checks) native checks, no simulator")
    }
}
