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
        let sessions = pendingSessions()
        guard !sessions.isEmpty else { return }

        var status = store.authorizationStatus(for: HKObjectType.workoutType())
        // Mirror sync(): a pending walk that was never decided must ask for
        // permission instead of silently discarding the record as skipped.
        if status == .notDetermined {
            do {
                try await store.requestAuthorization(toShare: HealthKitStore.writeTypes, read: [])
            } catch {
                sessions.forEach { setState(.skipped, session: $0) }
                return
            }
            status = store.authorizationStatus(for: HKObjectType.workoutType())
        }

        if status == .sharingAuthorized {
            for session in sessions {
                await write(session: session)
            }
        } else {
            sessions.forEach { setState(.skipped, session: $0) }
        }
    }

    /// Delete the Health workouts written for the given sessions (metadata
    /// keyed by GloWalkSessionID). No-op when Health is unavailable or the
    /// user hasn't granted write access — mirrors the write path.
    func deleteWorkouts(sessionIDs: [String]) async {
        guard store.isAvailable,
              store.authorizationStatus(for: HKObjectType.workoutType())
                == .sharingAuthorized else { return }
        for id in sessionIDs {
            do {
                try await store.deleteWorkouts(sessionID: id)
            } catch {
                Log.error("Health workout delete failed: \(error)")
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
                Log.error("Health sync state save error: \(error)")
            }
        }
    }
}
