import Foundation
import os

/// Unified logging facade — the single replacement for `print()` diagnostics.
///
/// Messages keep the existing `[Category] ...` prefix convention, which is
/// parsed into the os.Logger category so Console and Xcode can filter per
/// subsystem/category (e.g. `subsystem "GloWalk" category "Sensor"`). Logs are
/// cheap in Release and never appear on the user's screen.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "GloWalk"
    private static let categoryQueue = DispatchQueue(label: "glowalk.log.category")
    private static var cache: [String: Logger] = [:]

    private static func logger(for message: String) -> Logger {
        guard message.hasPrefix("["),
              let end = message.dropFirst().firstIndex(of: "]") else {
            return Logger(subsystem: subsystem, category: "general")
        }
        let category = String(message[message.index(after: message.startIndex)..<end])
        return categoryQueue.sync {
            if let existing = cache[category] { return existing }
            let created = Logger(subsystem: subsystem, category: category)
            cache[category] = created
            return created
        }
    }

    /// Debug-level diagnostic (most current call sites).
    static func debug(_ message: String) {
        logger(for: message).debug("\(message, privacy: .public)")
    }

    /// Error-level diagnostic (catch / failure paths).
    static func error(_ message: String) {
        logger(for: message).error("\(message, privacy: .public)")
    }
}
