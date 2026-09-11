import Foundation

/// Effective session time, excluding every paused/background interval.
struct WalkClock {
    private(set) var accumulated: TimeInterval = 0
    private(set) var resumedAt: Date?

    mutating func resume(at date: Date = Date()) {
        guard resumedAt == nil else { return }
        resumedAt = date
    }

    mutating func pause(at date: Date = Date()) {
        accumulated = elapsed(at: date)
        resumedAt = nil
    }

    func elapsed(at date: Date = Date()) -> TimeInterval {
        accumulated + (resumedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }
}
