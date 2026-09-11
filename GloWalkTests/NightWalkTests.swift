import XCTest
import CoreData
import HealthKit
@testable import GloWalk

@MainActor
final class NightWalkTests: XCTestCase {
    func testPauseExcludesElapsedTimeAndRepeatedTransitionsAreHarmless() {
        var clock = WalkClock()
        let start = Date(timeIntervalSince1970: 1000)
        clock.resume(at: start)
        clock.resume(at: start.addingTimeInterval(5))
        clock.pause(at: start.addingTimeInterval(60))
        clock.pause(at: start.addingTimeInterval(90))
        XCTAssertEqual(clock.elapsed(at: start.addingTimeInterval(300)), 60)
        clock.resume(at: start.addingTimeInterval(300))
        XCTAssertEqual(clock.elapsed(at: start.addingTimeInterval(330)), 90)
    }

    func testProjectionDoesNotBridgePausedMovement() throws {
        let points: [PathProjector.Point] = [
            .init(latitude: 30, longitude: 120, torchBrightness: 0.2, segmentID: 0),
            .init(latitude: 30.001, longitude: 120, torchBrightness: 0.2, segmentID: 0),
            .init(latitude: 31, longitude: 121, torchBrightness: 0.8, segmentID: 1),
            .init(latitude: 31.001, longitude: 121, torchBrightness: 0.8, segmentID: 1)
        ]
        let projector = try XCTUnwrap(PathProjector(points: points, area: CGRect(x: 0, y: 0, width: 10000, height: 10000)))
        var segments: [(CGPoint, CGPoint, Double)] = []
        projector.forEachSegment { start, end, _, _, light in segments.append((start, end, light)) }
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].0, projector.project(points[0]))
        XCTAssertEqual(segments[0].1, projector.project(points[1]))
        XCTAssertEqual(segments[1].0, projector.project(points[2]))
        XCTAssertEqual(segments[0].2, 0.2, accuracy: 0.001)
        XCTAssertEqual(segments[1].2, 0.8, accuracy: 0.001)
    }

    func testInterruptedRecoveryKeepsOnlyCompleteCheckpoint() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let complete = WalkSession.create(in: context, moonPhase: "full_moon", weatherCondition: nil)
        complete.totalSteps = 20
        complete.totalDistance = 14
        complete.activeDuration = 30
        complete.lastCheckpoint = Date()
        for lat in [30.0, 30.001] {
            _ = PathPoint.create(in: context, lat: lat, lon: 120, ambientLight: 0.2, torchBrightness: 0.5, session: complete)
        }
        let incomplete = WalkSession.create(in: context, moonPhase: "full_moon", weatherCondition: nil)
        incomplete.totalSteps = 12
        incomplete.activeDuration = 30
        persistence.save()
        persistence.recoverInterruptedWalks()
        let records = try context.fetch(NSFetchRequest<WalkSession>(entityName: "WalkSession"))
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.id, complete.id)
        XCTAssertEqual(complete.endTime, complete.lastCheckpoint)
        XCTAssertEqual(complete.healthSyncState, "pending")
        XCTAssertEqual(complete.duration, 30)
    }

    func testHealthPayloadUsesActiveDurationAndStableDistinctIdentifiers() {
        let context = PersistenceController(inMemory: true).container.viewContext
        let session = WalkSession.create(in: context, moonPhase: "new_moon", weatherCondition: nil)
        session.endTime = session.wrappedStartTime.addingTimeInterval(600)
        session.activeDuration = 240
        session.totalSteps = 100
        session.totalDistance = 70
        let first = HealthWorkoutFactory.workout(session: session)
        let retry = HealthWorkoutFactory.workout(session: session)
        XCTAssertEqual(first.duration, 240)
        XCTAssertEqual(first.metadata?[HKMetadataKeySyncIdentifier] as? String,
                       retry.metadata?[HKMetadataKeySyncIdentifier] as? String)
        let samples = HealthWorkoutFactory.samples(session: session)
        let ids = samples.compactMap { $0.metadata?[HKMetadataKeySyncIdentifier] as? String }
        XCTAssertEqual(Set(ids).count, 2)
        XCTAssertFalse(ids.contains(first.metadata?[HKMetadataKeySyncIdentifier] as? String ?? ""))
        XCTAssertFalse(HealthKitStore.writeTypes.contains(HKSeriesType.workoutRoute()))
        XCTAssertTrue(HealthWorkoutFactory.routeLocations(session: session).isEmpty)
    }

    func testUnreadableStorePreservesOriginalBytes() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let data = Data("unreadable original store".utf8)
        try data.write(to: url)
        defer {
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
        }
        let persistence = PersistenceController(storeURL: url)
        XCTAssertTrue(persistence.loadFailed)
        XCTAssertEqual(try Data(contentsOf: url), data)
        XCTAssertTrue(persistence.container.persistentStoreCoordinator.persistentStores.isEmpty)
    }

    func testNightMemoryIsStableForSameWalk() {
        let seed = NightMemoryRandom.seed(for: "walk-A")
        var first = NightMemoryRandom(seed: seed)
        var reopened = NightMemoryRandom(seed: seed)
        for _ in 0..<100 { XCTAssertEqual(first.next(), reopened.next()) }
        XCTAssertNotEqual(seed, NightMemoryRandom.seed(for: "walk-B"))
        let profile = NightMemoryProfile(duration: 60, distance: 50,
                                         moonPhase: "new_moon", weatherCondition: nil,
                                         samples: [])
        XCTAssertEqual(Tagline.nightMemory(for: profile, seed: seed).key,
                       Tagline.nightMemory(for: profile, seed: seed).key)
    }

    func testNightMemoryHasThreeStableVariantsAndPreservesOldKeys() {
        let keys = Set((0..<12).map {
            Tagline.nightMemory(key: "tagline.quiet", seed: UInt64($0)).key
        })
        XCTAssertEqual(keys.count, 3)
        let first = Tagline.nightMemory(key: "tagline.quiet", seed: 42)
        let second = Tagline.nightMemory(key: "tagline.quiet", seed: 42,
                                         excluding: [first.key])
        let third = Tagline.nightMemory(key: "tagline.quiet", seed: 42,
                                        excluding: [first.key, second.key])
        XCTAssertEqual(Set([first.key, second.key, third.key]).count, 3)
        XCTAssertTrue(keys.contains(Tagline.nightMemory(
            key: "tagline.quiet", seed: 42, excluding: keys).key))
        XCTAssertEqual(Tagline.savedNightMemory(key: "tagline.quiet")?.key,
                       "tagline.quiet")
        XCTAssertNil(Tagline.savedNightMemory(key: "tagline.quiet.missing"))
    }

    func testNightMemoryThemesComeFromWalkFacts() {
        func sample(_ lat: Double, _ lon: Double, _ light: Double = 0.5,
                    _ segment: Int64 = 0) -> NightMemoryProfile.Sample {
            .init(latitude: lat, longitude: lon,
                  torchBrightness: light, segmentID: segment)
        }
        func profile(duration: TimeInterval = 60, distance: Double = 50,
                     moon: String = "new_moon", weather: String? = nil,
                     samples: [NightMemoryProfile.Sample]) -> NightMemoryProfile {
            .init(duration: duration, distance: distance, moonPhase: moon,
                  weatherCondition: weather, samples: samples)
        }

        let straight = [sample(30, 120), sample(30.001, 120), sample(30.002, 120)]
        XCTAssertEqual(profile(weather: "rain", samples: straight).theme, .rain)
        XCTAssertEqual(profile(samples: [sample(30, 120, 0.5, 0),
                                          sample(30.001, 120, 0.5, 1)]).theme, .resumed)
        XCTAssertEqual(profile(samples: [sample(30, 120, 0.1),
                                          sample(30.001, 120, 0.5),
                                          sample(30.002, 120, 0.9)]).theme, .changingLight)
        let winding = [sample(30, 120), sample(30.001, 120),
                       sample(30.001, 120.001), sample(30.002, 120.001)]
        XCTAssertEqual(profile(samples: winding).theme, .winding)
        XCTAssertEqual(profile(duration: 1_500, distance: 1_700,
                               samples: straight).theme, .longWalk)
        XCTAssertEqual(profile(moon: "full_moon", samples: straight).theme, .moonlit)
        XCTAssertEqual(profile(samples: straight).theme, .quiet)
    }
}
