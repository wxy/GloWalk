import Foundation

enum FeatureFlags {
    /// Explicit opt-in for recording. Cannot be enabled in Release or on hardware.
    #if DEBUG && targetEnvironment(simulator)
    static let promoWalk = ProcessInfo.processInfo.arguments.contains("--promo-walk")
    #else
    static let promoWalk = false
    #endif

    /// Back-camera closed-loop torch control — shipped with 1.1.0. Kept as a
    /// flag so the loop can be toggled off for A/B or fallback without code
    /// changes.
    static let torchClosedLoop = true
}
