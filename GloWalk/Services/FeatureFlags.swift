enum FeatureFlags {
    /// Back-camera closed-loop torch control — shipped with 1.1.0. Kept as a
    /// flag so the loop can be toggled off for A/B or fallback without code
    /// changes.
    static let torchClosedLoop = true
}
