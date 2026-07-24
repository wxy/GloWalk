import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "GloWalk")
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        loadStores(recreatingOnFailure: !inMemory)
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    /// Load the store; if it fails (e.g. an incompatible model after an update),
    /// delete the on-disk store and retry once, then fall back to an in-memory
    /// store so the app still launches instead of crashing.
    private func loadStores(recreatingOnFailure: Bool) {
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        guard let error = loadError else { return }
        print("Core Data load failed: \(error.localizedDescription)")
        guard recreatingOnFailure else { return }

        if let url = container.persistentStoreDescriptions.first?.url {
            let fm = FileManager.default
            for suffix in ["", "-wal", "-shm"] {
                let sidecar = url.deletingLastPathComponent()
                    .appendingPathComponent(url.lastPathComponent + suffix)
                try? fm.removeItem(at: sidecar)
            }
        }

        var retryError: Error?
        container.loadPersistentStores { _, error in retryError = error }
        guard let retryError else { return }
        print("Core Data recovery failed, using in-memory store: \(retryError.localizedDescription)")
        container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        container.loadPersistentStores { _, _ in }
    }

    func save() {
        let context = container.viewContext
        if context.hasChanges {
            do { try context.save() } catch {
                print("Core Data save error: \(error)")
            }
        }
    }
}
