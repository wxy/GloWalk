import Foundation

/// 闭环只在"走路姿势 + 未被遮挡 + 未暂停 + 非白天"时激活。
struct LoopGate {
    let pitchDeg: Double
    let isOccluded: Bool
    let isDaylight: Bool
    let isTorchPaused: Bool

    var isActive: Bool {
        !isOccluded && !isTorchPaused && !isDaylight && pitchDeg >= 25 && pitchDeg <= 60
    }
}
