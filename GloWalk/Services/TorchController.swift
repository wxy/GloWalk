import Foundation

/// 手电闭环控制器：Y 低于目标 → 升一档；高于目标 → 降一档。
/// 死区 + 迟滞防震荡；每步最多 ±1 档即斜率限制；active=false 时冻结。
struct TorchController {
    let levels: [Double]
    let deadband: Double
    let hysteresis: Double
    private(set) var levelIndex = 0
    private var lastDirection = 0   // -1 刚降档, +1 刚升档, 0 初始

    init(levels: [Double], deadband: Double, hysteresis: Double) {
        self.levels = levels
        self.deadband = deadband
        self.hysteresis = hysteresis
    }

    /// Seed the controller at the nearest discrete level (e.g. the previous
    /// LightEngine target) so the loop doesn't start from 0 while the posture
    /// gate is inactive — otherwise the torch turns off at walk start and then
    /// ramps through every level when the gate first activates.
    mutating func seed(level: Double) {
        var best = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for (index, candidate) in levels.enumerated() {
            let distance = abs(candidate - level)
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        levelIndex = best
        lastDirection = 0
    }

    mutating func step(setpoint: Double, measured: Double, active: Bool) -> Double {
        guard active else { return levels[levelIndex] }
        let err = measured - setpoint
        let threshold = deadband + (lastDirection == 0 ? 0 : hysteresis)
        if err > threshold, levelIndex > 0 {
            levelIndex -= 1
            lastDirection = -1
        } else if err < -threshold, levelIndex < levels.count - 1 {
            levelIndex += 1
            lastDirection = 1
        }
        return levels[levelIndex]
    }
}
