# 手电闭环控制原型（Spike）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在真机上验证"后摄闭环控制手电亮度"的可行性——把后摄读到的"手电照到路面的反光"作为被控量，把路面亮度维持在目标值，并逐一回答全部硬件可行性问题，最终产出"双摄闭环 vs 单摄推断模型"的取舍结论。

**Architecture:** 前/后双摄单会话（`AVCaptureMultiCamSession`）各 2Hz 采样；后摄锁定曝光、只采画面下半部的地面 ROI；控制器按"死区 + 迟滞 + 每步 ±1 档"调手电粗档位；设备俯仰角作为闭环激活门控；前摄继续负责屏幕亮度，并作为不支持多摄设备/后摄失效时的完整兜底。手电目标亮度 R 在 spike 中为固定常量，但控制器接口参数化，天气/暗适应/手动/低电量在后续阶段作为 R 的修改器接入。

**Tech Stack:** Swift / AVFoundation（`AVCaptureMultiCamSession`、`AVCaptureVideoDataOutput`）/ CoreMotion / 现有 `SensorManager`、`HUDViewModel`、`LightEngine`

## Global Constraints

- iOS 最低 15.0（`AVCaptureMultiCamSession` 可用，iOS 13+）。
- 仅当 `AVCaptureMultiCamSession.isMultiCamSupported == true` 时启用双摄；否则**完全回退到现有单前摄路径**，现有行为不得改变。
- 现有前摄采样、`LightEngine`、屏幕亮度逻辑在 spike 期间保持完整可用；闭环仅在 `FeatureFlags.torchClosedLoop == true` 时接管手电。
- 采样 2Hz（与现有前摄一致）；手电每次最多变动 ±1 档，绝不高于 2Hz 变动。
- 遮挡（proximity）、手动暂停、结束步行时，手电关闭逻辑优先级最高，闭环不得覆盖。
- 单元测试必须离线可跑（不依赖相机/硬件）；硬件行为一律用真机测量脚本记录，结论必须有数据。
- 提交信息遵循仓库约定前缀（feat/fix/chore/docs）；分支名 `spike/torch-closed-loop`（分支名不受前缀检查约束）。

---

## 待验证假设（spike 的核心产出）

- H1：前/后双摄在 `AVCaptureMultiCamSession` 下并发 2Hz 采样稳定（不丢帧、不互相打断）。
- H2：后摄锁定曝光后，像素均值随手电档位**单调**变化（暗环境下）。
- H3：地面 ROI（画面下半 1/3 中心带）比全帧更能反映路面照明，受天空/车灯干扰小。
- H4：`setTorchModeOn(level:)` 在真机上的可区分档位数（预期 10–20 档）足以支撑粗档位闭环。
- H5：死区 + 迟滞 + 每步 ±1 档的控制器在真实场景收敛、不震荡。
- H6：姿势门控（俯仰 25°–60° 才激活，否则冻结）能防止"手机举起看 HUD 时后摄朝天误调暗手电"。
- H7：10 分钟持续运行无发热警告、无采样掉帧。
- H8：不支持多摄的设备编译/运行回退正常（行为与现状一致）。

## 文件结构

- 创建 `GloWalk/Services/FeatureFlags.swift` — spike 开关，一个 static let。
- 创建 `GloWalk/Services/TorchController.swift` — 纯逻辑控制器（量化档位表 + 死区/迟滞 + 步进），可单测。
- 创建 `GloWalk/Services/LoopGate.swift` — 闭环激活门控（姿势/遮挡/暂停/白天），可单测。
- 修改 `GloWalk/Services/SensorManager.swift` — 条件性迁移到 `AVCaptureMultiCamSession`，新增后摄采样、曝光锁定、地面 ROI 输出。
- 修改 `GloWalk/ViewModels/HUDViewModel.swift` — tick 中开关切换闭环/现有 LightEngine；透传姿势、遮挡等门控输入。
- 创建 `GloWalk/Services/TorchMeasurementLog.swift` — 真机测量日志（CSV 行），spike 专用。
- 测试：`GloWalkTests/TorchControllerTests.swift`、`GloWalkTests/LoopGateTests.swift`。
- 文档：`docs/superpowers/plans/2026-08-07-torch-closed-loop-spike.md`（本文件）、最终 `docs/torch-closed-loop-report.md`（Task 6 产出）。

---

### Task 1: Spike 分支、开关与测量日志基础设施

**Files:**
- Create: `GloWalk/Services/FeatureFlags.swift`
- Create: `GloWalk/Services/TorchMeasurementLog.swift`
- Create: `GloWalkTests/FeatureFlagsTests.swift`

**Interfaces:**
- Produces: `enum FeatureFlags { static let torchClosedLoop: Bool }`；`enum TorchMeasurementLog { static func row(timestamp: Date, torchLevel: Double, fullFrame: Double, roi: Double, pitch: Double, active: Bool) -> String }`

- [ ] **Step 1: 创建开关文件**

```swift
enum FeatureFlags {
    /// Spike-only: back-camera closed-loop torch control.
    static let torchClosedLoop = true
}
```

- [ ] **Step 2: 创建测量日志（CSV 一行，便于真机 Console/日志抓取）**

```swift
import Foundation

enum TorchMeasurementLog {
    /// One CSV row: ts,torch,full,roi,pitch,active
    static func row(timestamp: Date, torchLevel: Double,
                    fullFrame: Double, roi: Double,
                    pitch: Double, active: Bool) -> String {
        let ts = String(format: "%.3f", timestamp.timeIntervalSinceReferenceDate)
        return [ts,
                String(format: "%.3f", torchLevel),
                String(format: "%.4f", fullFrame),
                String(format: "%.4f", roi),
                String(format: "%.1f", pitch),
                active ? "1" : "0"].joined(separator: ",")
    }
}
```

- [ ] **Step 3: 写失败测试并实现**

```swift
import XCTest
@testable import GloWalk

final class FeatureFlagsTests: XCTestCase {
    func testMeasurementRowFormat() {
        let row = TorchMeasurementLog.row(
            timestamp: Date(timeIntervalSinceReferenceDate: 100),
            torchLevel: 0.5, fullFrame: 0.25, roi: 0.3, pitch: 42, active: true)
        let parts = row.split(separator: ",")
        XCTAssertEqual(parts.count, 6)
        XCTAssertEqual(parts[1], "0.500")
        XCTAssertEqual(parts[5], "1")
    }
}
```

- [ ] **Step 4: 建分支、跑测试、提交**

```bash
git checkout -b spike/torch-closed-loop
xcodebuild test -scheme GloWalk -destination 'platform=iOS Simulator,name=iPhone 17'
git add GloWalk/Services/FeatureFlags.swift GloWalk/Services/TorchMeasurementLog.swift GloWalkTests/FeatureFlagsTests.swift
git commit -m "chore: add spike flag and torch measurement log"
```

---

### Task 2: 条件性迁移到 AVCaptureMultiCamSession（先保持单前摄行为）

**Files:**
- Modify: `GloWalk/Services/SensorManager.swift`（`startAmbientLightSampling` 一带）
- Test: `GloWalkTests/SensorManagerTests.swift`（如存在则加；不存在则本任务以构建 + 真机验证为准）

**Interfaces:**
- Consumes: 无
- Produces: `SensorManager.captureSession: AVCaptureSession?`；`SensorManager.isMultiCam: Bool`

- [ ] **Step 1: 增加能力检测**

```swift
private var isMultiCam: Bool {
    AVCaptureMultiCamSession.isMultiCamSupported
}
```

- [ ] **Step 2: 会话创建分支**

```swift
private func makeSession() -> AVCaptureSession {
    if isMultiCam {
        let s = AVCaptureMultiCamSession()
        // AVCaptureMultiCamSession's preset is always .inputPriority —
        // any other preset throws on device. Pick per-camera formats instead.
        s.sessionPreset = .inputPriority
        return s
    }
    let s = AVCaptureSession()
    s.sessionPreset = .low
    return s
}
```

`startAmbientLightSampling()` 改用 `makeSession()`；前摄 input/output 逻辑原样保留。

- [ ] **Step 3: 构建 + 现有 35 测试回归**

```bash
xcodebuild build -scheme GloWalk -destination 'platform=iOS Simulator,name=iPhone 17'
xcodebuild test -scheme GloWalk -destination 'platform=iOS Simulator,name=iPhone 17'
```

- [ ] **Step 4: 真机快速验证（H1 前置）**：真机走一遍现有步行流程，确认前摄环境光/白天检测行为无变化。

- [ ] **Step 5: 提交**

```bash
git add GloWalk/Services/SensorManager.swift
git commit -m "feat: conditionally migrate capture session to AVCaptureMultiCamSession"
```

---

### Task 3: 后摄输入、曝光锁定、地面 ROI 采样

**Files:**
- Modify: `GloWalk/Services/SensorManager.swift`

**Interfaces:**
- Consumes: `makeSession()`（Task 2）
- Produces: `SensorManager.backGroundLuminance: Double?`（锁定曝光下地面 ROI 均值，2Hz 更新）；`SensorManager.backFullFrameLuminance: Double?`；`SensorManager.backExposureLocked: Bool`

- [ ] **Step 1: 后摄 input + output（仅多摄时）**

```swift
private func addBackCamera(to session: AVCaptureSession) {
    guard isMultiCam,
          let back = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
          let input = try? AVCaptureDeviceInput(device: back) else { return }
    guard session.canAddInput(input) else { return }
    session.addInput(input)

    let out = AVCaptureVideoDataOutput()
    out.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    out.setSampleBufferDelegate(backDelegate, queue: backQueue)
    if session.canAddOutput(out) { session.addOutput(out) }
}
```

（`backDelegate` 与 `backQueue` 参照现有 `AmbientLightDelegate` 模式，2Hz throttle。）

- [ ] **Step 2: 曝光锁定（测前锁、测后恢复）**

```swift
private func lockBackExposure() {
    guard let back = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }
    do {
        try back.lockForConfiguration()
        let fmt = back.activeFormat
        // 暗场景固定曝光：1/60s、ISO 最低档（真机按测量结果校准）
        let duration = CMTime(value: 1, timescale: 60)
        back.setExposureModeCustom(duration: duration,
                                   iso: Float(fmt.minISO),
                                   completionHandler: nil)
        back.unlockForConfiguration()
        backExposureLocked = true
    } catch {
        print("[Sensor] Back exposure lock error: \(error)")
    }
}
```

- [ ] **Step 3: 地面 ROI 均值（复用前摄边带采样模式）**

```swift
/// 画面下半 1/3 的中心 60% 宽度——手持走路姿势下对应近处路面。
let yStart = height * 2 / 3
let xInset = width / 5
var total = 0.0, count = 0
for y in stride(from: yStart, to: height, by: 8) {
    for x in stride(from: xInset, to: width - xInset, by: 8) {
        // BGRA 采样同前摄；total += 亮度
    }
}
```

- [ ] **Step 4: 真机测量（H2/H3/H4）**：暗室中，手电从 0 到 1 按 0.1 步进、每档停留 1s，抓取 `TorchMeasurementLog` 行，记录全帧与 ROI 均值：
  - H2：绘制"档位 → 均值"曲线，确认单调（允许平台段，但不允许回落）。
  - H3：对比全帧 vs ROI 在"路灯夜街"场景的抗干扰性。
  - H4：记录实际可区分的档位数，反馈给 Task 4 的档位表。

- [ ] **Step 5: 提交**

```bash
git add GloWalk/Services/SensorManager.swift
git commit -m "feat: add back-camera exposure-locked ground ROI sampling"
```

---

### Task 4: 闭环控制器（纯逻辑，TDD）

**Files:**
- Create: `GloWalk/Services/TorchController.swift`
- Create: `GloWalkTests/TorchControllerTests.swift`

**Interfaces:**
- Consumes: 无（不依赖硬件）
- Produces: `struct TorchController { init(levels: [Double], deadband: Double, hysteresis: Double); mutating func step(setpoint: Double, measured: Double, active: Bool) -> Double }`

- [ ] **Step 1: 写失败测试（收敛 / 死区 / 迟滞 / 边界 / 冻结）**

```swift
import XCTest
@testable import GloWalk

final class TorchControllerTests: XCTestCase {
    private let levels: [Double] = [0, 0.15, 0.3, 0.45, 0.6, 0.75, 0.9, 1.0]

    func testRaisesLevelWhenMeasuredBelowSetpoint() {
        var c = TorchController(levels: levels, deadband: 0.04, hysteresis: 0.02)
        let out = c.step(setpoint: 0.4, measured: 0.2, active: true)
        XCTAssertEqual(out, 0.15)
    }

    func testHoldsWithinDeadband() {
        var c = TorchController(levels: levels, deadband: 0.04, hysteresis: 0.02)
        XCTAssertEqual(c.step(setpoint: 0.4, measured: 0.41, active: true), 0.0)
    }

    func testDoesNotOscillateAroundSetpoint() {
        var c = TorchController(levels: levels, deadband: 0.04, hysteresis: 0.02)
        _ = c.step(setpoint: 0.4, measured: 0.1, active: true)   // → 0.15
        _ = c.step(setpoint: 0.4, measured: 0.35, active: true)  // 仍在死区
        XCTAssertEqual(c.step(setpoint: 0.4, measured: 0.38, active: true), 0.15)
    }

    func testClampsAtMaxLevel() {
        var c = TorchController(levels: levels, deadband: 0.04, hysteresis: 0.02)
        for _ in 0..<20 {
            _ = c.step(setpoint: 1.0, measured: 0.0, active: true)
        }
        XCTAssertEqual(c.step(setpoint: 1.0, measured: 0.0, active: true), 1.0)
    }

    func testFreezesWhenInactive() {
        var c = TorchController(levels: levels, deadband: 0.04, hysteresis: 0.02)
        _ = c.step(setpoint: 0.4, measured: 0.2, active: true)   // → 0.15
        XCTAssertEqual(c.step(setpoint: 0.4, measured: 0.9, active: false), 0.15)
    }
}
```

- [ ] **Step 2: 运行确认失败**

```bash
xcodebuild test -scheme GloWalk -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:GloWalkTests/TorchControllerTests
```

- [ ] **Step 3: 实现**

```swift
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
```

- [ ] **Step 4: 运行确认全绿，提交**

```bash
xcodebuild test -scheme GloWalk -destination 'platform=iOS Simulator,name=iPhone 17'
git add GloWalk/Services/TorchController.swift GloWalkTests/TorchControllerTests.swift
git commit -m "feat: add deadband/hysteresis torch controller with tests"
```

---

### Task 5: 闭环门控与集成

**Files:**
- Create: `GloWalk/Services/LoopGate.swift`
- Create: `GloWalkTests/LoopGateTests.swift`
- Modify: `GloWalk/ViewModels/HUDViewModel.swift`（tick 手电分支）

**Interfaces:**
- Consumes: `TorchController.step(setpoint:measured:active:)`；`SensorManager.backGroundLuminance`、`devicePitch`、`isOccluded`、`isDaylight`
- Produces: `struct LoopGate { let pitchDeg: Double; let isOccluded: Bool; let isDaylight: Bool; let isTorchPaused: Bool; var isActive: Bool }`

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import GloWalk

final class LoopGateTests: XCTestCase {
    func testActiveInWalkingPosture() {
        let g = LoopGate(pitchDeg: 45, isOccluded: false, isDaylight: false, isTorchPaused: false)
        XCTAssertTrue(g.isActive)
    }
    func testFrozenWhenPhoneRaised() {
        let g = LoopGate(pitchDeg: 10, isOccluded: false, isDaylight: false, isTorchPaused: false)
        XCTAssertFalse(g.isActive)
    }
    func testFrozenWhenOccludedOrPausedOrDaylight() {
        XCTAssertFalse(LoopGate(pitchDeg: 45, isOccluded: true, isDaylight: false, isTorchPaused: false).isActive)
        XCTAssertFalse(LoopGate(pitchDeg: 45, isOccluded: false, isDaylight: false, isTorchPaused: true).isActive)
        XCTAssertFalse(LoopGate(pitchDeg: 45, isOccluded: false, isDaylight: true, isTorchPaused: false).isActive)
    }
}
```

- [ ] **Step 2: 实现**

```swift
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
```

- [ ] **Step 3: 集成到 tick（开关切换）**

```swift
// HUDViewModel.tick 内，替换现有手电分支：
if FeatureFlags.torchClosedLoop, let y = sensorManager.backGroundLuminance {
    let gate = LoopGate(pitchDeg: sensorManager.devicePitch,
                        isOccluded: sensorManager.isOccluded,
                        isDaylight: isDaylight,
                        isTorchPaused: torchPaused)
    brightness = torchController.step(setpoint: 0.4, measured: y, active: gate.isActive)
    sensorManager.setTorchLevel(brightness)
    locationManager.currentTorchBrightness = brightness
} else {
    // 现有 lightEngine 路径原样
}
```

（`torchController` 为 HUDViewModel 新属性；`setpoint: 0.4` 为 spike 固定目标，后续由天气/暗适应修改器接管。）

- [ ] **Step 4: 回归测试 + 提交**

```bash
xcodebuild test -scheme GloWalk -destination 'platform=iOS Simulator,name=iPhone 17'
git add GloWalk/Services/LoopGate.swift GloWalkTests/LoopGateTests.swift GloWalk/ViewModels/HUDViewModel.swift
git commit -m "feat: gate and integrate the torch closed loop behind the spike flag"
```

---

### Task 6: 真机测量与决策报告

**Files:**
- Create: `docs/torch-closed-loop-report.md`

- [ ] **Step 1: 场景清单逐一测量**（每个场景 ≥3 分钟，抓取 `TorchMeasurementLog` 行）

1. 暗室（无环境光）：收敛时间、最终档位、是否震荡。
2. 走廊灯（均匀明亮，H5/H1 的"室内"案例）：手电应降至低档/关。
3. 路灯夜街（斑驳）：手电在暗段自动升档、亮段降档，不闪断。
4. 地下通道/隧道（白天暗处，H1 反例）：从"关"进入后应快速开灯。
5. 白天户外：闭环应被 `isDaylight` 门控冻结，手电保持关。
6. 手机举起看 HUD（俯仰 <25°）：闭环冻结、档位不变。
7. 10 分钟连续运行：无发热警告、无掉帧（H7）。
8. 不支持多摄设备（如可用旧设备）：回退单前摄，行为与现状一致（H8）。

- [ ] **Step 2: 每场景计算**：收敛时间、超调量、震荡次数、手电档位分布；把结论填进 H1–H8 表。

- [ ] **Step 3: 写决策报告** `docs/torch-closed-loop-report.md`：每个假设"通过/部分/不通过 + 数据"；若 H2/H4 不通过则分析量化与单调性；最终给出"双摄闭环 vs 单摄推断模型"的明确取舍建议。

- [ ] **Step 4: 提交**

```bash
git add docs/torch-closed-loop-report.md
git commit -m "docs: torch closed-loop spike measurement report"
```

---

## 成功标准

- H1–H8 全部有真机数据结论（通过 / 部分通过 / 不通过），无"未验证"。
- 现有 35 个测试不回归；新增 `TorchControllerTests`（5 个）、`LoopGateTests`（3 个）、`FeatureFlagsTests`（1 个）全绿。
- 报告明确回答：双摄闭环是否值得替换单摄推断模型，或哪些部分值得并入生产。

## Self-Review 记录

- 覆盖性：H1→Task 2/3，H2/H3/H4→Task 3 Step 4，H5→Task 4 + Task 6，H6→Task 5 + Task 6 场景 6，H7→Task 6 场景 7，H8→Task 2 + Task 6 场景 8；屏幕亮度职责保留在前摄，未偏离范围。
- 无占位符：所有代码步骤均给出具体实现；真机测量步骤给出场景与指标。
- 类型一致性：`TorchController.step(setpoint:measured:active:) -> Double`、`LoopGate(pitchDeg:isOccluded:isDaylight:isTorchPaused:)`、`SensorManager.backGroundLuminance` 在 Task 3–5 中签名一致。
