import XCTest
import CoreData
@testable import GloWalk

final class HealthModelMigrationTests: XCTestCase {
    /// 1.0.1 用户数据必须通过轻量迁移保留，且新属性初始为 nil。
    func testLightweightMigrationPreservesSessions() throws {
        let bundle = Bundle(for: WalkSession.self)
        let momd = bundle.url(forResource: "GloWalk", withExtension: "momd")
        guard let oldURL = momd?.appendingPathComponent("GloWalk.mom"),
              let newURL = momd?.appendingPathComponent("GloWalk 2.mom") else {
            XCTFail("Model versions not found in GloWalk.momd")
            return
        }
        guard let oldModel = NSManagedObjectModel(contentsOf: oldURL),
              let newModel = NSManagedObjectModel(contentsOf: newURL) else {
            XCTFail("Failed to load model versions")
            return
        }
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        defer { try? FileManager.default.removeItem(at: storeURL) }

        // 用旧模型写一条 1.0.1 风格的会话。
        let oldCoord = NSPersistentStoreCoordinator(managedObjectModel: oldModel)
        try oldCoord.addPersistentStore(ofType: NSSQLiteStoreType,
                                        configurationName: nil as String?,
                                        at: storeURL,
                                        options: nil as [AnyHashable: Any]?)
        let oldCtx = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        oldCtx.persistentStoreCoordinator = oldCoord
        let oldSession = WalkSession(context: oldCtx)
        oldSession.id = UUID()
        oldSession.startTime = Date()
        oldSession.endTime = Date().addingTimeInterval(600)
        oldSession.totalSteps = 1234
        oldSession.totalDistance = 850
        try oldCtx.save()

        // 用新模型 + 自动迁移打开同一 store。
        let newCoord = NSPersistentStoreCoordinator(managedObjectModel: newModel)
        try newCoord.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil as String?,
            at: storeURL,
            options: [NSMigratePersistentStoresAutomaticallyOption: true,
                      NSInferMappingModelAutomaticallyOption: true])
        let newCtx = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        newCtx.persistentStoreCoordinator = newCoord

        let request: NSFetchRequest<WalkSession> = NSFetchRequest(entityName: "WalkSession")
        let sessions = try newCtx.fetch(request)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.totalSteps, 1234)
        XCTAssertEqual(sessions.first?.totalDistance, 850)
        XCTAssertNil(sessions.first?.healthSyncState)
    }
}
