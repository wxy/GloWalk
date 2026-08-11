import Foundation

/// 热状态感知的手电降档策略：serious 封顶 0.6，critical 封顶 0.3，
/// nominal/fair 不限制。纯逻辑，可单测。
enum TorchThermalPolicy {
    static let seriousCap = 0.6
    static let criticalCap = 0.3

    static func cappedLevel(_ requested: Double,
                            thermalState: ProcessInfo.ThermalState) -> Double {
        switch thermalState {
        case .serious: return min(requested, seriousCap)
        case .critical: return min(requested, criticalCap)
        default: return requested
        }
    }
}
