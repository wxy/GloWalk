# GloWalk 1.1.0 — Apple Health 步行同步设计

> 日期：2026-08-11 · 状态：已与用户确认，待制定实施计划

## 背景与目标

1.1.0 增加「运动健康」支持：每次有效步行结束后，把该次步行写成 Apple Health 的一条完整「步行」体能训练（含步数、距离、时长与路线），让记录同时出现在「健康」与「健身」App 中。同步仅在用户授权后发生，只写入、不读取，数据不出设备。

## 已确认需求

- **记录形态**：`HKWorkout(activityType: .walking)` + 关联的步数样本、距离样本（`distanceWalkingRunning`）、`HKWorkoutRoute` 路线；时长 = `endTime − startTime`。
- **同步范围**：所有落库的有效会话（`totalSteps > 0`），包括 `completed` 与 `interrupted`（中断可能源于应用被系统杀掉，同样代表真实步行）。
- **授权时机**：首次出现可同步记录时自动请求写入权限；被拒后应用内不再弹权限框，只能通过「权限与隐私」页查看状态并引导跳转系统设置重新开启。
- **无开关**：同步不设开关——只要授权即写入；授权状态统一放在「权限与隐私」页展示。
- **无补录**：只同步授权以后新结束的记录；用户之前拒绝、未同步的记录，在之后授权时也**不**补录。
- **海报不进入健康**：HealthKit 不支持给训练记录附加图片；海报继续留在应用「历史」并支持保存相册/分享。训练记录通过自定义元数据 `GloWalkSessionID = 会话 UUID` 与应用内会话对应（健康 App 界面不显示该字段，程序可读）。

## 全局约束

- iOS 最低 15.0（`HKWorkoutRouteBuilder` 要求 iOS 11+，满足）。
- 仅 iPhone（现有 `SUPPORTED_PLATFORMS` 即 iphoneos/iphonesimulator；HealthKit 在 iPad 不可用）。
- 只写入 HealthKit，不请求任何读取权限；健康数据不离开设备（与 PRIVACY.md 承诺一致）。
- 同步异步执行，不得阻塞结束步行的 UI 与返回流程。
- 单测必须离线可跑：HKHealthStore 通过 protocol 抽象，测试用 mock。
- 数据模型变更必须保持已有用户数据（轻量迁移）；不得原地修改单一版本模型导致旧库不兼容。
- 提交信息遵循仓库约定前缀（feat/fix/chore/docs）。

## 架构与组件

新增两个文件，职责分离；其余为小改动。

### HealthKitStore（底层封装）

文件：`GloWalk/Services/HealthKitStore.swift`

- 实现 `HealthStoreProtocol`，内部持有 `HKHealthStore`。
- Protocol 暴露的最小接口：
  - `var isAvailable: Bool`（`HKHealthStore.isHealthDataAvailable()`）
  - `func authorizationStatus(for: HKObjectType) -> HKAuthorizationStatus`
  - `func requestAuthorization(toShare: Set<HKSampleType>, read: Set<HKObjectType>) async throws`
  - `func save(workout: HKWorkout, samples: [HKQuantitySample], route: HKWorkoutRoute?) async throws`
- 写入类型固定为：`stepCount`、`distanceWalkingRunning`、`HKWorkoutType.workoutType()`、`HKSeriesType.workoutRoute()`。

### HealthSyncService（编排）

文件：`GloWalk/Services/HealthSyncService.swift`

- 依赖注入 `HealthStoreProtocol` 与持久化上下文，便于单测。
- 公开 API：
  - `func sync(session: WalkSession) async` — 结束步行后调用；
  - `func retryPending() async` — 启动/回前台时调用；
  - `var isEnabled: Bool` / `func setEnabled(_:)` — 读写 `UserPreferences.healthSyncEnabled`。
- 决策规则见「数据流」。

### 模型与偏好

- `WalkSession` 新增可选属性 `healthSyncState: String?`（取值：nil / pending / synced / failed / skipped；nil = 不需要同步）。
- `UserPreferences` 新增 `@AppStorage("healthSyncEnabled") var healthSyncEnabled: Bool = true`（默认开，首次有效步行自动请求授权）。

### UI

- `PermissionsView`（权限与隐私页）新增健康权限卡片：状态 + 功能说明 + 跳系统设置入口。
- `ArrivalSummaryView` 增加同步状态提示（同步中 / 已同步 / 同步失败）。
- `HistoryListView` 行尾增加小图标表示已同步（仅 `synced`）。

## 数据流

### 结束步行时

1. `endWalkAndNotify` / `endWalkAbruptly` 保存会话后，调用 `HealthSyncService.sync(session:)`（Task 异步，不阻塞）。
2. `sync` 依次判断：
   - `healthSyncEnabled == false` 或 `isAvailable == false` → 不改变状态，直接返回；
   - 授权状态 `.notDetermined` → `requestAuthorization(...)`；请求完成后重新读取授权状态，若被拒 → 置 `skipped` 并返回（此后不再自动请求）；
   - 授权状态 `.denied` / `.sharingDenied` → 置 `skipped`，不请求、不重试；
   - 授权状态 `.authorized` → 置 `pending` → 构造并写入，成功置 `synced`，失败置 `failed`。
3. 写入内容：
   - `HKWorkout`：`activityType = .walking`；`start = session.startTime`；`end = session.endTime`；`duration = end − start`；`totalDistance = 距离（>0 时）`；`metadata = ["GloWalkSessionID": session.id.uuidString]`。
   - `HKQuantitySample`：步数（count，0 不写）、距离（meter，>0 时写）。
   - 路线：`pathPoints` 中有效坐标点 ≥ 2 时，用 `HKWorkoutRouteBuilder` 按时间序重建并关联；不足 2 点省略。
4. 状态写入 Core Data 并保存（与 `PersistenceController.save()` 一致）。

### 重试

- 启动（`GloWalkApp`）与回前台（`didBecomeActive`）时调用 `retryPending()`。
- 仅处理 `failed` / `pending` 的会话，且仅当授权状态为 `.authorized` 才重写；若用户已撤销授权 → 置 `skipped`。
- 重试不扩展同步范围：不处理 `nil`（授权前的老记录）与 `skipped`。

## 权限页展示

- 「权限与隐私」页（`PermissionsView`）新增健康卡片，与相机、定位卡片同构：
  - 状态：已授权 / 尚未授权（将在首次有效步行结束时请求）/ 已拒绝（点按跳转系统设置 `UIApplication.openSettingsURLString`）/ 此设备不支持。
  - 功能说明：步行结束后写入步数、距离、时长和路线；只写入、不读取。
- 授权文案（`NSHealthShareUsageDescription` / `NSHealthUpdateUsageDescription`，需中英繁三语，走现有字符串目录机制）：
  - 中文示例：「GloWalk 会把你的步行记录（步数、距离、时长和路线）写入健康 App，用于生成运动记录。数据仅保存在你的设备上，不会上传。」

## 错误处理

| 场景 | 行为 |
| --- | --- |
| 设备不支持 HealthKit | 权限页显示「此设备不支持」，不请求不写入 |
| 用户拒绝授权 | 该次置 `skipped`，以后不再弹窗 |
| 写入失败（临时错误） | 置 `failed`，下次启动/回前台重试 |
| 写入中应用被杀 | 状态保持 `pending`，下次启动重试 |
| 授权后被用户撤销 | 下次同步/重试时置 `skipped`，不再打扰 |
| 授权被拒绝 | 不写入；之后在系统设置重新授权后，仅新记录同步 |

## 数据模型变更与迁移

- 现有模型为单一版本 `GloWalk.xcdatamodeld/GloWalk.xcdatamodel`，已有线上用户数据（1.0.1）。
- 变更方式：在 `GloWalk.xcdatamodeld` 中新增模型版本（如 `GloWalk 2`），向 `WalkSession` 添加可选属性 `healthSyncState`（String，无默认值），并设为当前版本。
- `NSPersistentStoreDescription` 默认开启自动轻量迁移与推断映射，新增可选属性可安全迁移，不丢数据。
- 禁止直接原地修改单一版本模型（会导致旧库判为不兼容；现有 `PersistenceController` 的恢复逻辑会删除用户数据，不可接受）。

## 测试计划

`GloWalkTests/HealthSyncServiceTests.swift`，mock `HealthStoreProtocol`：

- 授权分支：notDetermined（请求→授权/拒绝）、denied（跳过）、authorized（写入）。
- 载荷：activityType、start/end/duration、步数与距离样本值、`GloWalkSessionID` 元数据、距离为 0 时省略样本。
- 路线：≥2 点重建、<2 点省略、无坐标点省略。
- 状态流转：nil→pending→synced / failed / skipped；isAvailable=false 不变更。
- 重试：仅 `failed`/`pending` 且已授权；撤销授权→skipped；`nil` 与 `skipped` 不处理。
- 迁移：新建临时 store，用旧模型写入会话后以新模型打开，验证数据保留且 `healthSyncState == nil`。

## 发布清单（App Store 影响）

- 两个 target 增加 HealthKit capability（`com.apple.developer.healthkit`）。
- 字符串目录新增 `NSHealthShareUsageDescription`、`NSHealthUpdateUsageDescription`（中英繁）。
- 更新 `PRIVACY.md`：健康数据仅按用户授权写入本机健康 App，不收集、不上传。
- App Store Connect：隐私标签「健康与健身」相关申报；提交时按问卷实际填写。
- 真机验证授权弹窗、写入、健康/健身 App 展示、路线展示；模拟器结果仅作参考。

## 明确不做（Out of scope）

- 不读取健康数据（如用系统步数校准）。
- 不做历史补录/批量导入。
- 不把海报附加到健康记录（平台不支持）。
- 不做后台 BGTaskScheduler 队列化同步（1.1.0 不必要）。
- 不做删除同步（用户删除会话不删除健康记录；如需，后续版本评估）。

## 待实施文件清单

- 新建 `GloWalk/Services/HealthKitStore.swift`
- 新建 `GloWalk/Services/HealthSyncService.swift`
- 新建 `GloWalkTests/HealthSyncServiceTests.swift`
- 修改 `GloWalk/Resources/GloWalk.xcdatamodeld`（新增模型版本 + healthSyncState）
- 修改 `GloWalk/Models/WalkSession.swift`
- 修改 `GloWalk/Models/UserPreferences.swift`
- 修改 `GloWalk/ViewModels/HUDViewModel.swift`
- 修改 `GloWalk/Views/Settings/SettingsView.swift`
- 修改 `GloWalk/Views/Poster/ArrivalSummaryView.swift`
- 修改 `GloWalk/Views/History/HistoryListView.swift`
- 修改 `GloWalk/Resources/InfoPlist.xcstrings`（含 pbxproj 的 `INFOPLIST_KEY_*` 设置）
- 修改 `GloWalk/GloWalk.entitlements` 与 `GloWalk.xcodeproj/project.pbxproj`
- 修改 `PRIVACY.md`
