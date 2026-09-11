import CoreData
import Combine

final class PersistenceController: ObservableObject {
    static let shared = PersistenceController()
    let container: NSPersistentContainer
    @Published private(set) var loadFailed = false

    init(inMemory: Bool = false, storeURL: URL? = nil) {
        container = NSPersistentContainer(name: "GloWalk")
        if let storeURL { container.persistentStoreDescriptions.first?.url = storeURL }
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        container.persistentStoreDescriptions.first?.shouldMigrateStoreAutomatically = true
        container.persistentStoreDescriptions.first?.shouldInferMappingModelAutomatically = true
        loadStores()
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    /// Never delete an unreadable store or silently start an empty replacement.
    func loadStores() {
        container.loadPersistentStores { _, error in
            self.loadFailed = error != nil
            if let error { Log.error("Core Data load failed: \(error.localizedDescription)") }
        }
    }

    /// Finish only complete checkpointed fragments after process termination.
    /// Missing sensor data is never synthesized to make an incomplete walk pass.
    func recoverInterruptedWalks() {
        guard !loadFailed else { return }
        let request: NSFetchRequest<WalkSession> = NSFetchRequest(entityName: "WalkSession")
        request.predicate = NSPredicate(format: "endTime == nil")
        do {
            for session in try container.viewContext.fetch(request) {
                if session.isCompleteRecord, let checkpoint = session.lastCheckpoint {
                    session.endTime = checkpoint
                    session.endType = "interrupted"
                    session.healthSyncState = HealthSyncState.pending.rawValue
                } else {
                    container.viewContext.delete(session)
                }
            }
            save()
        } catch { Log.error("Walk recovery failed: \(error)") }
    }

    func save() {
        guard !loadFailed else { return }
        let context = container.viewContext
        if context.hasChanges {
            do { try context.save() } catch { Log.error("Core Data save error: \(error)") }
        }
    }
}
