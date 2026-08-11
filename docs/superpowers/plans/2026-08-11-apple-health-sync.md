# Apple Health 步行同步 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 1.1.0 中把每次有效步行（步数 > 0）结束后落库的会话同步为 Apple Health 的一条完整「步行」体能训练（步数、距离、时长、路线），并提供设置开关、授权管理与失败重试。

**Architecture:** 新增 `HealthKitStore`（HKHealthStore 的 protocol 封装，可 mock）与 `HealthSyncService`（编排：授权判断、写入、状态流转、重试）。纯数据构造放在 `HealthWorkoutFactory`，便于离线单测。`WalkSession` 新增 `healthSyncState` 属性（新增 Core Data 模型版本，轻量迁移保留 1.0.1 用户数据）。结束步行后异步调用同步；启动/回前台重试失败记录。设置页新增「健康」分组，海报与历史列表展示同步状态。

**Tech Stack:** Swift / HealthKit / Core Data / SwiftUI / XCTest

**Branch:** `feat/apple-health-sync`（由 `spike/torch-closed-loop` 切出，包含设计文档与隐私清单）

## Global Constraints

- iOS 最低 15.0（`HKWorkoutRouteBuilder` 要求 iOS 11+，满足；异步 HealthKit API 均可用）。
- 仅 iPhone（现有 `SUPPORTED_PLATFORMS` 即 iphoneos/iphonesimulator；HealthKit 在 iPad 不可用）。
- 只写入 HealthKit，不请求任何读取权限；健康数据不离开设备。
- 同步异步执行，不得阻塞结束步行的 UI 与返回流程。
- 单测必须离线可跑：HKHealthStore 通过 `HealthStoreProtocol` 抽象，测试用 mock。
- 数据模型变更必须保持已有用户数据：新增模型版本 `GloWalk 2.xcdatamodel` 做轻量迁移，**禁止**原地修改单一版本模型。
- 只同步授权以后新结束的记录（`healthSyncState` 为 nil 的老记录永不同步、不补录）。
- 被拒绝授权后应用内不再弹权限框，只能通过设置页跳系统设置重新开启。
- 提交信息遵循仓库约定前缀（feat/fix/chore/docs）。

## 文件结构

| 文件 | 职责 | 动作 |
| --- | --- | --- |
| `GloWalk/Resources/GloWalk.xcdatamodeld/GloWalk 2.xcdatamodel/contents` | 新模型版本，WalkSession 增加 `healthSyncState` | 新建 |
| `GloWalk/Resources/GloWalk.xcdatamodeld/.xccurrentversion` | 指向当前模型版本 | 新建 |
| `GloWalk/Models/WalkSession.swift` | 声明 `healthSyncState` | 修改 |
| `GloWalk/Services/HealthWorkoutFactory.swift` | 纯函数：由会话构造 HKWorkout/样本/路线坐标 | 新建 |
| `GloWalk/Services/HealthKitStore.swift` | HKHealthStore 封装 + `HealthStoreProtocol` | 新建 |
| `GloWalk/Services/HealthSyncService.swift` | 编排：授权、写入、状态、重试 | 新建 |
| `GloWalk/Models/UserPreferences.swift` | `healthSyncEnabled` 开关（默认开） | 修改 |
| `GloWalk/ViewModels/HUDViewModel.swift` | 结束步行后调用同步；发布 `healthSyncStatus` | 修改 |
| `GloWalk/ContentView.swift` | 回前台/启动时 `retryPending()` | 修改 |
| `GloWalk/Views/Settings/SettingsView.swift` | 「健康」分组：开关 + 状态 + 跳系统设置 | 修改 |
| `GloWalk/Views/Poster/ArrivalSummaryView.swift` | 到达海报页显示同步状态 | 修改 |
| `GloWalk/Views/History/HistoryListView.swift` | 历史行尾显示已同步图标 | 修改 |
| `GloWalk/Extensions/L10n.swift` | 新增 11 个本地化键 | 修改 |
| `GloWalk/Resources/Localizable.xcstrings` | 新增键的三语翻译 | 修改 |
| `GloWalk/Resources/InfoPlist.xcstrings` | 新增两个健康用途说明 | 修改 |
| `GloWalk/GloWalk.entitlements` | 增加 HealthKit capability | 修改 |
| `GloWalk.xcodeproj/project.pbxproj` | 增加 `INFOPLIST_KEY_NSHealth*UsageDescription` | 修改 |
| `PRIVACY.md` | 补充健康数据说明 | 修改 |
| `GloWalkTests/HealthModelMigrationTests.swift` | 迁移测试 | 新建 |
| `GloWalkTests/HealthWorkoutFactoryTests.swift` | 载荷构造测试 | 新建 |
| `GloWalkTests/HealthSyncServiceTests.swift` | 服务编排测试（含 MockHealthStore） | 新建 |

工程为 Xcode 16+ 同步文件夹（objectVersion 77），`GloWalk/` 与 `GloWalkTests/` 下的新文件会自动纳入 target，无需手动改 pbxproj 文件引用。

---

### Task 1: Core Data 模型版本 + `healthSyncState`

**Files:**
- Test: `GloWalkTests/HealthModelMigrationTests.swift`
- Create: `GloWalk/Resources/GloWalk.xcdatamodeld/GloWalk 2.xcdatamodel/contents`
- Create: `GloWalk/Resources/GloWalk.xcdatamodeld/.xccurrentversion`
- Modify: `GloWalk/Models/WalkSession.swift`

**Interfaces:**
- Consumes: 现有 `WalkSession` 实体（`startTime/endTime/totalSteps/totalDistance/id`）。
- Produces: `WalkSession.healthSyncState: String?`（取值 nil / `"pending"` / `"synced"` / `"failed"` / `"skipped"`）。

- [ ] **Step 1: Write the failing migration test**

`GloWalkTests/HealthModelMigrationTests.swift`:

```swift
import XCTest
import CoreData
@testable import GloWalk

final class HealthModelMigrationTests: XCTestCase {
    /// 1.0.1 用户数据必须通过轻量迁移保留，且新属性初始为 nil。
    func testLightweightMigrationPreservesSessions() throws {
        let bundle = Bundle(for: PersistenceController.self)
        guard let momd = bundle.url(forResource: "GloWalk", withExtension: "momd"),
              let oldURL = momd.appendingPathComponent("GloWalk.mom"),
              let newURL = momd.appendingPathComponent("GloWalk 2.mom") else {
            XCTFail("Model versions not found in GloWalk.momd")
            return
        }
        let oldModel = try NSManagedObjectModel(contentsOf: oldURL)
        let newModel = try NSManagedObjectModel(contentsOf: newURL)
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        defer { try? FileManager.default.removeItem(at: storeURL) }

        // 用旧模型写一条 1.0.1 风格的会话。
        let oldCoord = NSPersistentStoreCoordinator(managedObjectModel: oldModel)
        try oldCoord.addPersistentStore(ofType: NSSQLiteStoreType,
                                        configurationName: nil,
                                        at: storeURL, options: nil)
        let oldCtx = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        oldCtx.persistentStoreCoordinator = oldCoord
        let oldSession = WalkSession(context: oldCtx)
        oldSession.id = UUID()
        oldSession.startTime = Date()
        oldSession.endTime = Date().addingTimeInterval(600)
        oldSession.totalSteps = 1234
        oldSession.totalDistance = 850
        try oldCtx.save()

        // 用新模型 + 自动迁移打开同一 store。
        let newCoord = NSPersistentStoreCoordinator(managedObjectModel: newModel)
        try newCoord.addPersistentStore(
            ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL,
            options: [NSMigratePersistentStoresAutomaticallyOption: true,
                      NSInferMappingModelAutomaticallyOption: true])
        let newCtx = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        newCtx.persistentStoreCoordinator = newCoord

        let request: NSFetchRequest<WalkSession> = WalkSession.fetchRequest()
        let sessions = try newCtx.fetch(request)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.totalSteps, 1234)
        XCTAssertEqual(sessions.first?.totalDistance, 850)
        XCTAssertNil(sessions.first?.healthSyncState)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project GloWalk.xcodeproj -scheme GloWalk -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:GloWalkTests/HealthModelMigrationTests`
Expected: FAIL（`GloWalk 2.mom` 尚不存在 → "Model versions not found"）。

- [ ] **Step 3: Create the new model version**

新建 `GloWalk/Resources/GloWalk.xcdatamodeld/GloWalk 2.xcdatamodel/contents`（内容为旧模型 + `healthSyncState` 属性）：

```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="22225" systemVersion="23F79" minimumToolsVersion="Automatic" sourceLanguage="Swift" usedWithSwiftData="NO" userDefinedModelVersionIdentifier="">
    <entity name="WalkSession" representedClassName="WalkSession" syncable="YES">
        <attribute name="avgLightLevel" optional="YES" attributeType="Double" defaultValueString="0.0" usesScalarValueType="YES"/>
        <attribute name="endTime" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
        <attribute name="endType" optional="YES" attributeType="String" defaultValueString="interrupted"/>
        <attribute name="healthSyncState" optional="YES" attributeType="String"/>
        <attribute name="id" optional="YES" attributeType="UUID" usesScalarValueType="NO"/>
        <attribute name="moonPhase" optional="YES" attributeType="String"/>
        <attribute name="posterImageData" optional="YES" attributeType="Binary"/>
        <attribute name="startTime" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
        <attribute name="totalDistance" optional="YES" attributeType="Double" defaultValueString="0.0" usesScalarValueType="YES"/>
        <attribute name="totalSteps" optional="YES" attributeType="Integer 64" defaultValueString="0" usesScalarValueType="YES"/>
        <attribute name="weatherCondition" optional="YES" attributeType="String"/>
        <relationship name="pathPoints" optional="YES" toMany="YES" deletionRule="Cascade" destinationEntity="PathPoint" inverseName="session" inverseEntity="PathPoint"/>
    </entity>
    <entity name="PathPoint" representedClassName="PathPoint" syncable="YES">
        <attribute name="ambientLight" optional="YES" attributeType="Double" defaultValueString="0.0" usesScalarValueType="YES"/>
        <attribute name="latitude" optional="YES" attributeType="Double" defaultValueString="0.0" usesScalarValueType="YES"/>
        <attribute name="longitude" optional="YES" attributeType="Double" defaultValueString="0.0" usesScalarValueType="YES"/>
        <attribute name="timestamp" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
        <attribute name="torchBrightness" optional="YES" attributeType="Double" defaultValueString="0.0" usesScalarValueType="YES"/>
        <relationship name="session" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="WalkSession" inverseName="pathPoints" inverseEntity="WalkSession"/>
    </entity>
</model>
```

新建 `GloWalk/Resources/GloWalk.xcdatamodeld/.xccurrentversion`：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>_XCCurrentVersionName</key>
	<string>GloWalk 2.xcdatamodel</string>
</dict>
</plist>
```

在 `GloWalk/Models/WalkSession.swift` 的 `@NSManaged public var endType: String?` 之后新增一行：

```swift
    @NSManaged public var healthSyncState: String?
```

- [ ] **Step 4: Run test to verify it passes**

Run: 同上 `-only-testing:GloWalkTests/HealthModelMigrationTests`
Expected: PASS（Xcode 会把两个版本编译进 `GloWalk.momd`，轻量迁移成功、数据保留）。

- [ ] **Step 5: Commit**

```bash
git add GloWalk/Resources/GloWalk.xcdatamodeld GloWalk/Models/WalkSession.swift GloWalkTests/HealthModelMigrationTests.swift
git commit -m "feat: add healthSyncState to WalkSession model"
```

---

### Task 2: HealthWorkoutFactory（纯载荷构造）

**Files:**
- Create: `GloWalk/Services/HealthWorkoutFactory.swift`
- Test: `GloWalkTests/HealthWorkoutFactoryTests.swift`

**Interfaces:**
- Consumes: `WalkSession`（`startTime/endTime/totalSteps/totalDistance/id/pathPointsArray`）。
- Produces:
  - `HealthWorkoutFactory.sessionIDMetadataKey: String`（值 `"GloWalkSessionID"`）
  - `HealthWorkoutFactory.workout(session:) -> HKWorkout`
  - `HealthWorkoutFactory.samples(session:) -> [HKQuantitySample]`
  - `HealthWorkoutFactory.routeLocations(session:) -> [CLLocation]`（有效坐标点 < 2 时返回空数组）

- [ ] **Step 1: Write the failing tests**

`GloWalkTests/HealthWorkoutFactoryTests.swift`:

```swift
import XCTest
import HealthKit
import CoreLocation
@testable import GloWalk

@MainActor
final class HealthWorkoutFactoryTests: XCTestCase {
    private func makeSession() -> (WalkSession, NSManagedObjectContext) {
        let ctx = PersistenceController(inMemory: true).container.viewContext
        let session = WalkSession(context: ctx)
        session.id = UUID()
        session.startTime = Date(timeIntervalSinceReferenceDate: 1000)
        session.endTime = Date(timeIntervalSinceReferenceDate: 1600)
        session.totalSteps = 1200
        session.totalDistance = 900
        _ = PathPoint.create(in: ctx, lat: 31.0, lon: 121.0,
                             ambientLight: 0.5, torchBrightness: 0.8, session: session)
        _ = PathPoint.create(in: ctx, lat: 31.01, lon: 121.01,
                             ambientLight: 0.5, torchBrightness: 0.8, session: session)
        try? ctx.save()
        return (session, ctx)
    }

    func testWorkoutPayload() {
        let (session, _) = makeSession()
        let workout = HealthWorkoutFactory.workout(session: session)
        XCTAssertEqual(workout.workoutActivityType, .walking)
        XCTAssertEqual(workout.startDate, session.startTime)
        XCTAssertEqual(workout.endDate, session.endTime)
        XCTAssertEqual(workout.duration, 600, accuracy: 0.001)
        XCTAssertEqual(workout.totalDistance?.doubleValue(for: .meter()), 900, accuracy: 0.001)
        XCTAssertEqual(workout.metadata?[HealthWorkoutFactory.sessionIDMetadataKey] as? String,
                       session.id?.uuidString)
    }

    func testSamplesOnlyWhenPositive() {
        let ctx = PersistenceController(inMemory: true).container.viewContext
        let session = WalkSession(context: ctx)
        session.id = UUID()
        session.startTime = Date(timeIntervalSinceReferenceDate: 1000)
        session.endTime = Date(timeIntervalSinceReferenceDate: 1600)
        session.totalSteps = 0
        session.totalDistance = 0
        try? ctx.save()

        let samples = HealthWorkoutFactory.samples(session: session)
        XCTAssertTrue(samples.isEmpty)
    }

    func testSamplesContent() {
        let (session, _) = makeSession()
        let samples = HealthWorkoutFactory.samples(session: session)
        XCTAssertEqual(samples.count, 2)
        let steps = samples.first { $0.quantityType == HKQuantityType.quantityType(forIdentifier: .stepCount) }
        let distance = samples.first { $0.quantityType == HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) }
        XCTAssertEqual(steps?.quantity.doubleValue(for: .count()), 1200, accuracy: 0.001)
        XCTAssertEqual(distance?.quantity.doubleValue(for: .meter()), 900, accuracy: 0.001)
    }

    func testRouteLocationsRequiresTwoPoints() {
        let ctx = PersistenceController(inMemory: true).container.viewContext
        let session = WalkSession(context: ctx)
        session.id = UUID()
        session.startTime = Date()
        _ = PathPoint.create(in: ctx, lat: 31.0, lon: 121.0,
                             ambientLight: 0.5, torchBrightness: 0.8, session: session)
        try? ctx.save()
        XCTAssertTrue(HealthWorkoutFactory.routeLocations(session: session).isEmpty)
    }

    func testRouteLocationsSortedAndFiltered() {
        let (session, _) = makeSession()
        let locations = HealthWorkoutFactory.routeLocations(session: session)
        XCTAssertEqual(locations.count, 2)
        XCTAssertEqual(locations[0].coordinate.latitude, 31.0, accuracy: 0.0001)
        XCTAssertEqual(locations[1].coordinate.longitude, 121.01, accuracy: 0.0001)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project GloWalk.xcodeproj -scheme GloWalk -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:GloWalkTests/HealthWorkoutFactoryTests`
Expected: FAIL（`HealthWorkoutFactory` 不存在，编译失败）。

- [ ] **Step 3: Implement the factory**

`GloWalk/Services/HealthWorkoutFactory.swift`:

```swift
import Foundation
import HealthKit
import CoreLocation
import CoreData

/// 由 WalkSession 构造 HealthKit 载荷的纯逻辑。不依赖 HKHealthStore，可离线单测。
enum HealthWorkoutFactory {
    static let sessionIDMetadataKey = "GloWalkSessionID"

    static func workout(session: WalkSession) -> HKWorkout {
        let start = session.startTime ?? Date()
        let end = session.endTime ?? start
        let distance = session.totalDistance
        return HKWorkout(
            activityType: .walking,
            start: start,
            end: end,
            duration: end.timeIntervalSince(start),
            totalEnergyBurned: nil,
            totalDistance: distance > 0 ? HKQuantity(unit: .meter(), doubleValue: distance) : nil,
            metadata: [sessionIDMetadataKey: session.id?.uuidString ?? UUID().uuidString]
        )
    }

    static func samples(session: WalkSession) -> [HKQuantitySample] {
        let start = session.startTime ?? Date()
        let end = session.endTime ?? start
        var result: [HKQuantitySample] = []
        if session.totalSteps > 0 {
            result.append(HKQuantitySample(
                type: HKQuantityType.quantityType(forIdentifier: .stepCount)!,
                quantity: HKQuantity(unit: .count(), doubleValue: Double(session.totalSteps)),
                start: start, end: end))
        }
        if session.totalDistance > 0 {
            result.append(HKQuantitySample(
                type: HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!,
                quantity: HKQuantity(unit: .meter(), doubleValue: session.totalDistance),
                start: start, end: end))
        }
        return result
    }

    static func routeLocations(session: WalkSession) -> [CLLocation] {
        let points = session.pathPointsArray
            .filter { $0.latitude != 0 || $0.longitude != 0 }
            .sorted { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) }
        guard points.count >= 2 else { return [] }
        return points.map { point in
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: point.latitude,
                                                   longitude: point.longitude),
                altitude: 0,
                horizontalAccuracy: 10,
                verticalAccuracy: -1,
                course: -1,
                speed: -1,
                timestamp: point.timestamp ?? Date())
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: 同上 `-only-testing:GloWalkTests/HealthWorkoutFactoryTests`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add GloWalk/Services/HealthWorkoutFactory.swift GloWalkTests/HealthWorkoutFactoryTests.swift
git commit -m "feat: add HealthKit payload factory with tests"
```

---

### Task 3: HealthStoreProtocol + HealthKitStore

**Files:**
- Create: `GloWalk/Services/HealthKitStore.swift`
- Test: 本任务由 Task 4 的 mock 覆盖协议形状；本任务先建立可编译的协议与实现。

**Interfaces:**
- Consumes: `HealthWorkoutFactory` 的产出类型；`[CLLocation]`。
- Produces:
  - `protocol HealthStoreProtocol`：`isAvailable: Bool`、`authorizationStatus(for:)`、`requestAuthorization(toShare:read:) async throws`、`save(workout:samples:routeLocations:) async throws`
  - `final class HealthKitStore: HealthStoreProtocol`（`HealthKitStore.writeTypes: Set<HKSampleType>` 静态常量）

- [ ] **Step 1: Implement the protocol and store**

`GloWalk/Services/HealthKitStore.swift`:

```swift
import HealthKit
import CoreLocation

protocol HealthStoreProtocol {
    var isAvailable: Bool { get }
    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus
    func requestAuthorization(toShare: Set<HKSampleType>, read: Set<HKObjectType>) async throws
    func save(workout: HKWorkout, samples: [HKQuantitySample], routeLocations: [CLLocation]) async throws
}

enum HealthStoreError: Error {
    case routeAddFailed
    case routeFinishFailed
}

final class HealthKitStore: HealthStoreProtocol {
    static let writeTypes: Set<HKSampleType> = [
        HKQuantityType.quantityType(forIdentifier: .stepCount)!,
        HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!,
        HKObjectType.workoutType() as HKSampleType,
        HKSeriesType.workoutRoute() as HKSampleType,
    ]

    private let healthStore = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus {
        healthStore.authorizationStatus(for: type)
    }

    func requestAuthorization(toShare typesToShare: Set<HKSampleType>,
                              read typesToRead: Set<HKObjectType>) async throws {
        try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
    }

    func save(workout: HKWorkout, samples: [HKQuantitySample],
              routeLocations: [CLLocation]) async throws {
        // workout 必须先保存，finishRoute 才能把路线关联到它。
        try await healthStore.save([workout] + samples)
        // iOS 26 SDK 的 HKWorkoutRouteBuilder 改为 healthStore/device 初始化器；
        // 用 #available 保护，低版本系统只保存训练与样本、省略路线。
        if #available(iOS 18.0, *), routeLocations.count >= 2 {
            let builder = HKWorkoutRouteBuilder(healthStore: healthStore, device: nil)
            try await builder.insertRouteData(routeLocations)
            let route = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<HKWorkoutRoute, Error>) in
                builder.finishRoute(with: workout,
                                    metadata: workout.metadata) { route, error in
                    if let route { cont.resume(returning: route) } else {
                        cont.resume(throwing: error ?? HealthStoreError.routeFinishFailed)
                    }
                }
            }
            _ = route
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild build -project GloWalk.xcodeproj -scheme GloWalk -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: BUILD SUCCEEDED。

> 实现说明：Xcode 26 / iOS 26 SDK 已移除 `HKWorkoutRouteBuilder(activityType:route:)`，改用 `init(healthStore:device:)` + `insertRouteData(_:)` + `finishRoute(with:metadata:)`，且要求 workout 先保存；路线以 `#available(iOS 18.0, *)` 保护，低版本只保存训练与样本（真机验收时确认路线展示）。

- [ ] **Step 3: Commit**

```bash
git add GloWalk/Services/HealthKitStore.swift
git commit -m "feat: add HealthKit store wrapper behind protocol"
```

---

### Task 4: HealthSyncService + MockHealthStore

**Files:**
- Create: `GloWalk/Services/HealthSyncService.swift`
- Test: `GloWalkTests/HealthSyncServiceTests.swift`（内含 `MockHealthStore`）
- Modify: `GloWalk/Models/UserPreferences.swift`

**Interfaces:**
- Consumes: `HealthStoreProtocol`、`HealthKitStore.writeTypes`、`HealthWorkoutFactory`、`WalkSession.healthSyncState`、`UserPreferences.healthSyncEnabled`。
- Produces:
  - `enum HealthSyncState: String { case pending, synced, failed, skipped }`
  - `@MainActor final class HealthSyncService`：`init(store:context:enabledProvider:)`、`var isEnabled: Bool`、`func sync(session:) async`、`func retryPending() async`
  - `UserPreferences.healthSyncEnabled: Bool`（`@AppStorage("healthSyncEnabled")`，默认 true）

- [ ] **Step 1: Add the preference**

在 `GloWalk/Models/UserPreferences.swift` 的 `@AppStorage("language")` 行后新增：

```swift
    @AppStorage("healthSyncEnabled") var healthSyncEnabled: Bool = true
```

- [ ] **Step 2: Write the failing service tests**

`GloWalkTests/HealthSyncServiceTests.swift`:

```swift
import XCTest
import CoreData
import HealthKit
import CoreLocation
@testable import GloWalk

@MainActor
final class HealthSyncServiceTests: XCTestCase {
    private var context: NSManagedObjectContext!

    override func setUp() {
        super.setUp()
        context = PersistenceController(inMemory: true).container.viewContext
    }

    private func makeSession(steps: Int64 = 100, distance: Double = 80,
                             state: String? = nil) -> WalkSession {
        let session = WalkSession(context: context)
        session.id = UUID()
        session.startTime = Date(timeIntervalSinceReferenceDate: 1000)
        session.endTime = Date(timeIntervalSinceReferenceDate: 1500)
        session.totalSteps = steps
        session.totalDistance = distance
        session.healthSyncState = state
        try? context.save()
        return session
    }

    func testAuthorizationFlowRequestsThenWrites() async {
        let mock = MockHealthStore(status: .notDetermined)
        mock.statusAfterRequest = .authorized
        let service = HealthSyncService(store: mock, context: context,
                                        enabledProvider: { true })
        let session = makeSession()

        await service.sync(session: session)

        XCTAssertEqual(mock.requestCallCount, 1)
        XCTAssertEqual(mock.savedWorkout?.workoutActivityType, .walking)
        XCTAssertEqual(mock.savedSamples.count, 2)
        XCTAssertEqual(session.healthSyncState, HealthSyncState.synced.rawValue)
    }

    func testDeniedAfterRequestSkips() async {
        let mock = MockHealthStore(status: .notDetermined)
        mock.statusAfterRequest = .denied
        let service = HealthSyncService(store: mock, context: context,
                                        enabledProvider: { true })
        let session = makeSession()

        await service.sync(session: session)

        XCTAssertEqual(mock.requestCallCount, 1)
        XCTAssertNil(mock.savedWorkout)
        XCTAssertEqual(session.healthSyncState, HealthSyncState.skipped.rawValue)
    }

    func testAlreadyDeniedSkipsWithoutRequest() async {
        let mock = MockHealthStore(status: .denied)
        let service = HealthSyncService(store: mock, context: context,
                                        enabledProvider: { true })
        let session = makeSession()

        await service.sync(session: session)

        XCTAssertEqual(mock.requestCallCount, 0)
        XCTAssertEqual(session.healthSyncState, HealthSyncState.skipped.rawValue)
    }

    func testDisabledToggleDoesNothing() async {
        let mock = MockHealthStore(status: .authorized)
        let service = HealthSyncService(store: mock, context: context,
                                        enabledProvider: { false })
        let session = makeSession()

        await service.sync(session: session)

        XCTAssertNil(mock.savedWorkout)
        XCTAssertNil(session.healthSyncState)
    }

    func testUnavailableStoreDoesNothing() async {
        let mock = MockHealthStore(status: .authorized)
        mock.isAvailable = false
        let service = HealthSyncService(store: mock, context: context,
                                        enabledProvider: { true })
        let session = makeSession()

        await service.sync(session: session)

        XCTAssertNil(mock.savedWorkout)
        XCTAssertNil(session.healthSyncState)
    }

    func testSaveFailureMarksFailed() async {
        let mock = MockHealthStore(status: .authorized)
        mock.saveError = HealthStoreError.routeFinishFailed
        let service = HealthSyncService(store: mock, context: context,
                                        enabledProvider: { true })
        let session = makeSession()

        await service.sync(session: session)

        XCTAssertEqual(session.healthSyncState, HealthSyncState.failed.rawValue)
    }

    func testRetryOnlyPendingAndFailed() async {
        let mock = MockHealthStore(status: .authorized)
        let service = HealthSyncService(store: mock, context: context,
                                        enabledProvider: { true })
        let pending = makeSession(state: HealthSyncState.pending.rawValue)
        let failed = makeSession(state: HealthSyncState.failed.rawValue)
        let skipped = makeSession(state: HealthSyncState.skipped.rawValue)
        let old = makeSession(state: nil)   // 授权前的老记录，永不补录

        await service.retryPending()

        XCTAssertEqual(pending.healthSyncState, HealthSyncState.synced.rawValue)
        XCTAssertEqual(failed.healthSyncState, HealthSyncState.synced.rawValue)
        XCTAssertEqual(skipped.healthSyncState, HealthSyncState.skipped.rawValue)
        XCTAssertNil(old.healthSyncState)
        XCTAssertEqual(mock.savedWorkouts.count, 2)
    }

    func testRetryMarksSkippedWhenRevoked() async {
        let mock = MockHealthStore(status: .denied)
        let service = HealthSyncService(store: mock, context: context,
                                        enabledProvider: { true })
        let failed = makeSession(state: HealthSyncState.failed.rawValue)

        await service.retryPending()

        XCTAssertEqual(failed.healthSyncState, HealthSyncState.skipped.rawValue)
        XCTAssertNil(mock.savedWorkout)
    }
}

@MainActor
private final class MockHealthStore: HealthStoreProtocol {
    var isAvailable: Bool
    var status: HKAuthorizationStatus
    var statusAfterRequest: HKAuthorizationStatus?
    var requestError: Error?
    var saveError: Error?
    var requestCallCount = 0
    private(set) var savedWorkout: HKWorkout?
    private(set) var savedWorkouts: [HKWorkout] = []
    private(set) var savedSamples: [HKQuantitySample] = []

    init(status: HKAuthorizationStatus, isAvailable: Bool = true) {
        self.status = status
        self.isAvailable = isAvailable
    }

    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus { status }

    func requestAuthorization(toShare: Set<HKSampleType>, read: Set<HKObjectType>) async throws {
        requestCallCount += 1
        if let statusAfterRequest { status = statusAfterRequest }
        if let requestError { throw requestError }
    }

    func save(workout: HKWorkout, samples: [HKQuantitySample],
              routeLocations: [CLLocation]) async throws {
        if let saveError { throw saveError }
        savedWorkout = workout
        savedWorkouts.append(workout)
        savedSamples = samples
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `xcodebuild test -project GloWalk.xcodeproj -scheme GloWalk -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:GloWalkTests/HealthSyncServiceTests`
Expected: FAIL（`HealthSyncService`、`MockHealthStore` 引用不到 `HealthStoreProtocol` 尚未暴露——协议无访问级别时对 @testable 可见，编译失败点是 `HealthSyncService` 不存在）。

- [ ] **Step 4: Implement the service**

`GloWalk/Services/HealthSyncService.swift`:

```swift
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
    private let enabledProvider: () -> Bool

    init(store: HealthStoreProtocol,
         context: NSManagedObjectContext,
         enabledProvider: @escaping () -> Bool = { UserPreferences.shared.healthSyncEnabled }) {
        self.store = store
        self.context = context
        self.enabledProvider = enabledProvider
    }

    var isEnabled: Bool {
        get { enabledProvider() }
        set { UserPreferences.shared.healthSyncEnabled = newValue }
    }

    func sync(session: WalkSession) async {
        guard enabledProvider(), store.isAvailable else { return }
        let status = store.authorizationStatus(for: HKObjectType.workoutType())
        switch status {
        case .notDetermined:
            do {
                try await store.requestAuthorization(toShare: HealthKitStore.writeTypes, read: [])
            } catch {
                setState(.skipped, session: session)
                return
            }
            if store.authorizationStatus(for: HKObjectType.workoutType()) == .authorized {
                await write(session: session)
            } else {
                setState(.skipped, session: session)
            }
        case .authorized:
            await write(session: session)
        default:
            setState(.skipped, session: session)
        }
    }

    func retryPending() async {
        guard enabledProvider(), store.isAvailable else { return }
        let status = store.authorizationStatus(for: HKObjectType.workoutType())
        let sessions = pendingSessions()
        for session in sessions {
            if status == .authorized {
                await write(session: session)
            } else {
                setState(.skipped, session: session)
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
        let request: NSFetchRequest<WalkSession> = WalkSession.fetchRequest()
        request.predicate = NSPredicate(
            format: "healthSyncState IN %@",
            [HealthSyncState.pending.rawValue, HealthSyncState.failed.rawValue])
        return (try? context.fetch(request)) ?? []
    }

    private func setState(_ state: HealthSyncState, session: WalkSession) {
        session.healthSyncState = state.rawValue
        if context.hasChanges {
            do { try context.save() } catch {
                print("Health sync state save error: \(error)")
            }
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: 同上 `-only-testing:GloWalkTests/HealthSyncServiceTests`
Expected: PASS（8 个用例）。

- [ ] **Step 6: Commit**

```bash
git add GloWalk/Services/HealthSyncService.swift GloWalkTests/HealthSyncServiceTests.swift GloWalk/Models/UserPreferences.swift
git commit -m "feat: add health sync service with tests"
```

---

### Task 5: 结束步行集成 + 回前台重试

**Files:**
- Modify: `GloWalk/ViewModels/HUDViewModel.swift`
- Modify: `GloWalk/ContentView.swift`

**Interfaces:**
- Consumes: `HealthSyncService`、`HealthKitStore`、`PersistenceController.shared.container.viewContext`。
- Produces: `HUDViewModel.healthSyncStatus: String?`（nil = 无提示；取值同 `HealthSyncState` rawValue）。

- [ ] **Step 1: Add the service and published status to HUDViewModel**

在 `GloWalk/ViewModels/HUDViewModel.swift` 的属性区新增（类已标注 `@MainActor`）：

```swift
    private let healthSyncService = HealthSyncService(
        store: HealthKitStore(),
        context: PersistenceController.shared.container.viewContext)
    @Published var healthSyncStatus: String?
```

- [ ] **Step 2: Hook both end-walk paths**

在 `endWalkAndNotify()` 中，`s.endType = "completed"` 与 `PersistenceController.shared.save()` 之后、`showArrivalSummary = true` 之前插入：

```swift
            Task {
                healthSyncStatus = HealthSyncState.pending.rawValue
                await healthSyncService.sync(session: s)
                healthSyncStatus = s.healthSyncState
            }
```

在 `endWalkAbruptly()` 中，保存分支的 `PersistenceController.shared.save()` 之后插入：

```swift
            Task {
                await healthSyncService.sync(session: s)
            }
```

零步数删除分支保持不变（不调用同步）。

- [ ] **Step 3: Add retry on foreground in ContentView**

在 `GloWalk/ContentView.swift` 的 `@Environment(\.scenePhase)` 之后新增私有方法：

```swift
    private func retryHealthSync() {
        let service = HealthSyncService(
            store: HealthKitStore(),
            context: PersistenceController.shared.container.viewContext)
        Task { await service.retryPending() }
    }
```

在 `.onChange(of: scenePhase)` 闭包开头加入：

```swift
            if phase == .active {
                retryHealthSync()
            }
```

（启动与回前台都会触发 `.active`，覆盖规格中的两个重试时机。）

- [ ] **Step 4: Build**

Run: `xcodebuild build -project GloWalk.xcodeproj -scheme GloWalk -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: BUILD SUCCEEDED。

- [ ] **Step 5: Commit**

```bash
git add GloWalk/ViewModels/HUDViewModel.swift GloWalk/ContentView.swift
git commit -m "feat: sync walks to Health on walk end and retry on foreground"
```

---

### Task 6: 设置页、到达页与历史列表 UI + 本地化

**Files:**
- Modify: `GloWalk/Extensions/L10n.swift`
- Modify: `GloWalk/Resources/Localizable.xcstrings`
- Modify: `GloWalk/Views/Settings/SettingsView.swift`
- Modify: `GloWalk/Views/Poster/ArrivalSummaryView.swift`
- Modify: `GloWalk/Views/History/HistoryListView.swift`

**Interfaces:**
- Consumes: `UserPreferences.healthSyncEnabled`、`HealthKitStore`、`HUDViewModel.healthSyncStatus`、`HealthSyncState`。

- [ ] **Step 1: Add L10n keys**

在 `GloWalk/Extensions/L10n.swift` 的 settings 区域末尾新增：

```swift
    static var settingsHealth: LocalizedStringKey { "settings.health" }
    static var settingsHealthSync: LocalizedStringKey { "settings.health.sync" }
    static var settingsHealthStatus: LocalizedStringKey { "settings.health.status" }
    static var settingsHealthAuthorized: LocalizedStringKey { "settings.health.authorized" }
    static var settingsHealthNotDetermined: LocalizedStringKey { "settings.health.notDetermined" }
    static var settingsHealthDenied: LocalizedStringKey { "settings.health.denied" }
    static var settingsHealthUnavailable: LocalizedStringKey { "settings.health.unavailable" }
    static var summaryHealthSyncing: LocalizedStringKey { "summary.health.syncing" }
    static var summaryHealthSynced: LocalizedStringKey { "summary.health.synced" }
    static var summaryHealthFailed: LocalizedStringKey { "summary.health.failed" }
```

- [ ] **Step 2: Add translations to Localizable.xcstrings**

在 `GloWalk/Resources/Localizable.xcstrings` 的顶层 `"strings"` 字典内（与其他键平级）追加以下 JSON 块（en/zh-Hans/zh-Hant 三语）：

```json
    "settings.health" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Health" } },
        "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "健康" } },
        "zh-Hant" : { "stringUnit" : { "state" : "translated", "value" : "健康" } }
      }
    },
    "settings.health.sync" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Sync to Health" } },
        "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "同步到健康" } },
        "zh-Hant" : { "stringUnit" : { "state" : "translated", "value" : "同步到健康" } }
      }
    },
    "settings.health.status" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Health Authorization" } },
        "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "健康授权状态" } },
        "zh-Hant" : { "stringUnit" : { "state" : "translated", "value" : "健康授權狀態" } }
      }
    },
    "settings.health.authorized" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Authorized" } },
        "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "已授权" } },
        "zh-Hant" : { "stringUnit" : { "state" : "translated", "value" : "已授權" } }
      }
    },
    "settings.health.notDetermined" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Not authorized yet — requested at the first walk end" } },
        "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "尚未授权（首次步行结束时请求）" } },
        "zh-Hant" : { "stringUnit" : { "state" : "translated", "value" : "尚未授權（首次步行結束時請求）" } }
      }
    },
    "settings.health.denied" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Denied — open Settings to enable" } },
        "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "已拒绝，可前往系统设置开启" } },
        "zh-Hant" : { "stringUnit" : { "state" : "translated", "value" : "已拒絕，可前往系統設定開啟" } }
      }
    },
    "settings.health.unavailable" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Health data unavailable on this device" } },
        "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "此设备不支持健康数据" } },
        "zh-Hant" : { "stringUnit" : { "state" : "translated", "value" : "此裝置不支援健康資料" } }
      }
    },
    "summary.health.syncing" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Syncing to Health…" } },
        "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "正在同步到健康…" } },
        "zh-Hant" : { "stringUnit" : { "state" : "translated", "value" : "正在同步到健康…" } }
      }
    },
    "summary.health.synced" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Synced to Health" } },
        "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "已同步到健康" } },
        "zh-Hant" : { "stringUnit" : { "state" : "translated", "value" : "已同步到健康" } }
      }
    },
    "summary.health.failed" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Sync failed — will retry later" } },
        "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "同步失败，稍后自动重试" } },
        "zh-Hant" : { "stringUnit" : { "state" : "translated", "value" : "同步失敗，稍後自動重試" } }
      }
    }
```

- [ ] **Step 3: Add the Health section to SettingsView**

在 `GloWalk/Views/Settings/SettingsView.swift` 顶部 `import CoreLocation` 后新增 `import HealthKit`。在 body 的 `Form` 中，`dataSection` 所在 Section 之后新增：

```swift
                    Section { healthSection } header: { sectionHeader(L10n.settingsHealth) }
```

在 `// MARK: - Sections` 区域新增：

```swift
    private var healthSection: some View {
        let store = HealthKitStore()
        return Group {
            Toggle(isOn: $prefs.healthSyncEnabled) {
                Text(L10n.settingsHealthSync).font(.gloBody(14)).foregroundColor(.white)
            }
            .tint(.gloGold)
            .disabled(!store.isAvailable)
            Button(action: openHealthSettings) {
                HStack {
                    Text(L10n.settingsHealthStatus).font(.gloBody(14)).foregroundColor(.white)
                    Spacer()
                    Text(healthStatusText(store))
                        .font(.gloBody(12))
                        .foregroundColor(healthStatusColor(store))
                }
            }
        }
    }

    private func healthStatusText(_ store: HealthKitStore) -> LocalizedStringKey {
        guard store.isAvailable else { return L10n.settingsHealthUnavailable }
        switch store.authorizationStatus(for: HKObjectType.workoutType()) {
        case .authorized: return L10n.settingsHealthAuthorized
        case .notDetermined: return L10n.settingsHealthNotDetermined
        default: return L10n.settingsHealthDenied
        }
    }

    private func healthStatusColor(_ store: HealthKitStore) -> Color {
        guard store.isAvailable else { return .white.opacity(0.3) }
        switch store.authorizationStatus(for: HKObjectType.workoutType()) {
        case .authorized: return .green.opacity(0.7)
        case .notDetermined: return .white.opacity(0.5)
        default: return .red.opacity(0.5)
        }
    }

    private func openHealthSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
```

- [ ] **Step 4: Add sync status to ArrivalSummaryView**

在 `GloWalk/Views/Poster/ArrivalSummaryView.swift` 的按钮 HStack 上方（`Spacer()` 之后）新增：

```swift
                        if let status = viewModel.healthSyncStatus {
                            Text(healthStatusLabel(status))
                                .font(.gloBody(12))
                                .foregroundColor(status == HealthSyncState.synced.rawValue
                                                 ? .green.opacity(0.8)
                                                 : .white.opacity(0.6))
                                .padding(.bottom, 8)
                        }
```

并在文件内新增私有方法：

```swift
    private func healthStatusLabel(_ status: String) -> LocalizedStringKey {
        switch status {
        case HealthSyncState.synced.rawValue: return L10n.summaryHealthSynced
        case HealthSyncState.failed.rawValue: return L10n.summaryHealthFailed
        default: return L10n.summaryHealthSyncing
        }
    }
```

- [ ] **Step 5: Add synced badge to HistoryListView**

在 `GloWalk/Views/History/HistoryListView.swift` 行内 `Spacer()` 与 chevron 之间新增：

```swift
                                        if session.healthSyncState == HealthSyncState.synced.rawValue {
                                            Image(systemName: "heart.fill")
                                                .font(.system(size: 10))
                                                .foregroundColor(.green)
                                        }
```

- [ ] **Step 6: Build**

Run: `xcodebuild build -project GloWalk.xcodeproj -scheme GloWalk -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: BUILD SUCCEEDED。

- [ ] **Step 7: Commit**

```bash
git add GloWalk/Extensions/L10n.swift GloWalk/Resources/Localizable.xcstrings GloWalk/Views/Settings/SettingsView.swift GloWalk/Views/Poster/ArrivalSummaryView.swift GloWalk/Views/History/HistoryListView.swift
git commit -m "feat: add Health sync settings, arrival status, history badge"
```

---

### Task 7: 工程配置（entitlement、用途文案）与隐私政策

**Files:**
- Modify: `GloWalk/GloWalk.entitlements`
- Modify: `GloWalk.xcodeproj/project.pbxproj`
- Modify: `GloWalk/Resources/InfoPlist.xcstrings`
- Modify: `PRIVACY.md`

**Interfaces:**
- Consumes: 无（纯配置）。

- [ ] **Step 1: Add the HealthKit entitlement**

在 `GloWalk/GloWalk.entitlements` 的 `<dict>` 中、`weatherkit` 键旁新增：

```xml
	<key>com.apple.developer.healthkit</key>
	<true/>
```

- [ ] **Step 2: Add usage-description build settings**

在 `GloWalk.xcodeproj/project.pbxproj` 中，两个**应用 target** 的 `XCBuildConfiguration`（即包含 `CODE_SIGN_ENTITLEMENTS = GloWalk/GloWalk.entitlements;` 的两个块，当前约在 352 与 443 行）的 `INFOPLIST_KEY_NSMotionUsageDescription` 行后各新增：

```
				INFOPLIST_KEY_NSHealthShareUsageDescription = "GloWalk writes your walking records (steps, distance, duration and route) to the Health app. Data stays on your device.";
				INFOPLIST_KEY_NSHealthUpdateUsageDescription = "GloWalk writes your walking records (steps, distance, duration and route) to the Health app. Data stays on your device.";
```

- [ ] **Step 3: Add localized usage descriptions to InfoPlist.xcstrings**

在 `GloWalk/Resources/InfoPlist.xcstrings` 的 `"strings"` 字典内追加：

```json
    "NSHealthShareUsageDescription" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "GloWalk writes your walking records (steps, distance, duration and route) to the Health app. Data stays on your device." } },
        "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "GloWalk 会把你的步行记录（步数、距离、时长和路线）写入健康 App，用于生成运动记录。数据仅保存在你的设备上，不会上传。" } },
        "zh-Hant" : { "stringUnit" : { "state" : "translated", "value" : "GloWalk 會把你的步行記錄（步數、距離、時長和路線）寫入健康 App，用於生成運動記錄。資料僅保存在你的裝置上，不會上傳。" } }
      }
    },
    "NSHealthUpdateUsageDescription" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "GloWalk writes your walking records (steps, distance, duration and route) to the Health app. Data stays on your device." } },
        "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "GloWalk 会把你的步行记录（步数、距离、时长和路线）写入健康 App，用于生成运动记录。数据仅保存在你的设备上，不会上传。" } },
        "zh-Hant" : { "stringUnit" : { "state" : "translated", "value" : "GloWalk 會把你的步行記錄（步數、距離、時長和路線）寫入健康 App，用於生成運動記錄。資料僅保存在你的裝置上，不會上傳。" } }
      }
    }
```

- [ ] **Step 4: Update PRIVACY.md**

在 `PRIVACY.md` 的 "Data That Stays On Your Device" 列表末尾追加：

```markdown
- **Apple Health (HealthKit)** — With your explicit permission, GloWalk writes your completed walking sessions (steps, distance, duration and route) to the Health app as workout records. GloWalk only writes; it never reads Health data, and no health data is transmitted off your device. You can disable this at any time in Settings → Health.
```

- [ ] **Step 5: Build to verify configuration is valid**

Run: `xcodebuild build -project GloWalk.xcodeproj -scheme GloWalk -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: BUILD SUCCEEDED（模拟器不校验 entitlement 签名；真机归档时 Xcode 需要开发者账号具备 HealthKit capability）。

- [ ] **Step 6: Commit**

```bash
git add GloWalk/GloWalk.entitlements GloWalk.xcodeproj/project.pbxproj GloWalk/Resources/InfoPlist.xcstrings PRIVACY.md
git commit -m "chore: add HealthKit entitlement and usage descriptions"
```

---

### Task 8: 全量验证

**Files:**
- 无（验证与冒烟）。

- [ ] **Step 1: Run the full test suite**

Run: `xcodebuild test -project GloWalk.xcodeproj -scheme GloWalk -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: 全部测试 PASS（含既有 GloWalkTests 与新增 3 个测试文件）。

- [ ] **Step 2: Simulator smoke test**

在模拟器运行 app（`xcodebuild -scheme GloWalk -destination 'platform=iOS Simulator,name=iPhone 17'` 后点 Run）：
- 设置页出现「健康」分组，开关默认开；
- 完成一次带步数的步行（可用模拟器步行模拟），到达页出现「正在同步到健康…」随后「已同步到健康」；
- 系统健康 App（模拟器自带）能看到该次步行训练与步数/距离样本；
- 历史列表该行出现 ❤ 图标。

- [ ] **Step 3: 真机验收清单（发布前）**

真机（iPhone，已登录开发者账号、HealthKit capability 可用）：
- 首次有效步行结束自动弹出健康授权；拒绝后不再弹窗，设置页显示「已拒绝」并可跳转系统设置；
- 授权后新步行写入：健康/健身 App 显示「步行」训练，含步数、距离、时长；
- 路线显示：健身 App 训练详情出现路线地图（验证 `HKWorkoutRouteBuilder` 关联）；
- 飞行模式下结束步行：状态为「同步失败」，恢复网络后回前台自动补写为「已同步」；
- 系统设置里撤销健康权限后：下一次结束步行置为「已跳过」，不再打扰；
- 1.0.1 存量数据升级安装后仍可打开，历史数据完整（迁移验证）。
- App Store Connect 提交时按隐私问卷申报「健康与健身」：健康数据仅按用户授权写入本机，不用于追踪。

- [ ] **Step 4: Push branch and open PR**

```bash
git push -u origin feat/apple-health-sync
gh pr create --base master --head feat/apple-health-sync --title "feat: sync walks to Apple Health" --body "实现 Apple Health 步行同步（设计：docs/superpowers/specs/2026-08-11-apple-health-sync-design.md）"
```

---

## Self-Review

- **Spec 覆盖**：完整训练记录（Task 2/4）、有效会话含 interrupted（Task 5 两个结束路径）、首次自动授权与拒绝后不再弹（Task 4）、无补录（Task 4 retry 测试断言 nil 记录不动）、海报不进健康 + 元数据会话 ID（Task 2）、设置开关/状态/跳系统设置（Task 6）、失败重试（Task 4/5）、模型版本迁移（Task 1）、发布清单中的 entitlement/文案/PRIVACY/真机验收（Task 7/8）。
- **占位符**：无 TBD/TODO；所有代码步骤含完整内容。
- **类型一致性**：`HealthStoreProtocol.save(workout:samples:routeLocations:)` 在 Task 3 定义、Task 4 调用与 mock 实现一致；`HealthSyncState` rawValue 在 Task 4 定义、Task 5/6 消费一致；`healthSyncEnabled` 键名在 Task 4 定义、Task 6 绑定一致。
