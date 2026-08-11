import Foundation
import CoreData
import HealthKit

enum HealthSyncState: String {
    case pending, synced, failed, skipped
}

@MainActor
final class HealthSyncService {
    private let store: HealthStoreProtocol
    private let context: NSManagedObjectContext

    init(store: HealthStoreProtocol, context: NSManagedObjectContext) {
        self.store = store
        self.context = context
    }

    func sync(session: WalkSession) async {
        guard store.isAvailable else { return }
        let status = store.authorizationStatus(for: HKObjectType.workoutType())
        switch status {
        case .notDetermined:
            do {
                try await store.requestAuthorization(toShare: HealthKitStore.writeTypes, read: [])
            } catch {
                setState(.skipped, session: session)
                return
            }
            if store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized {
                await write(session: session)
            } else {
                setState(.skipped, session: session)
            }
        case .sharingAuthorized:
            await write(session: session)
        case .sharingDenied:
            setState(.skipped, session: session)
        @unknown default:
            setState(.skipped, session: session)
        }
    }

    func retryPending() async {
        guard store.isAvailable else { return }
        let status = store.authorizationStatus(for: HKObjectType.workoutType())
        let sessions = pendingSessions()
        for session in sessions {
            if status == .sharingAuthorized {
                await write(session: session)
            } else {
                setState(.skipped, session: session)
            }
        }
    }

    private func write(session: WalkSession) async {
        setState(.pending, session: session)
        do {
            try await store.save(
                workout: HealthWorkoutFactory.workout(session: session),
                samples: HealthWorkoutFactory.samples(session: session),
                routeLocations: HealthWorkoutFactory.routeLocations(session: session))
            setState(.synced, session: session)
        } catch {
            setState(.failed, session: session)
        }
    }

    private func pendingSessions() -> [WalkSession] {
        let request: NSFetchRequest<WalkSession> = NSFetchRequest(entityName: "WalkSession")
        request.predicate = NSPredicate(
            format: "healthSyncState IN %@",
            [HealthSyncState.pending.rawValue, HealthSyncState.failed.rawValue])
        return (try? context.fetch(request)) ?? []
    }

    private func setState(_ state: HealthSyncState, session: WalkSession) {
        session.healthSyncState = state.rawValue
        if context.hasChanges {
            do { try context.save() } catch {
                print("Health sync state save error: \(error)")
            }
        }
    }
}
