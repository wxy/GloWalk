import SwiftUI
import AVFoundation
import CoreLocation

@MainActor
final class HUDViewModel: ObservableObject {
    @Published var brightness: Double = 0.7
    @Published var isActive: Bool = false
    @Published private(set) var isPaused = false
    @Published private(set) var usesClosedLoop = false
    private var walkClock = WalkClock()
    private var completedSteps = 0

    var canSaveWalk: Bool {
        (isPaused ? completedSteps : completedSteps + sensorManager.stepCount) > 0 && locationManager.totalDistance > 0
            && (currentWalkSession?.pathPointsArray.count ?? 0) >= 2 && walkClock.elapsed() > 0
    }
    @Published var elapsedDistance: String = String(format: L10n.hudDistanceMeters, 0.0)
    private var displayDistance: Double = 0
    @Published var elapsedMinutes: Int = 0
    @Published var batteryPercentage: Int = 100
    @Published var stepCount: Int = 0
    @Published var isTorchOccluded: Bool = false
    /// True while the thermal cap (serious/critical) has actually reduced the
    /// torch output — drives the HUD notice so the dimming never looks like a
    /// mystery.
    @Published var isThermalNoticeVisible: Bool = false
    /// True when camera permission is denied — ambient light sensing unavailable.
    @Published var cameraDeniedForAmbient: Bool = false
    @Published var pathPoints: [PathPoint] = []
    @Published var gpsActive: Bool = false
    /// GPS fix accuracy in meters (CLLocation.horizontalAccuracy), nil when no
    /// fix is available. Drives the HUD signal-strength indicator — path points
    /// are only recorded when accuracy is < 30m, so a weak signal delays drawing.
    @Published var gpsAccuracyMeters: Double?
    @Published var currentHeading: Double = 0
    /// Current screen brightness the app is applying (0–1) — feeds the HUD's
    /// counterclockwise ring. Updated every tick so it responds immediately to
    /// ambient changes.
    @Published var screenBrightness: Double = 0.5
    /// UI brightness boost factor: 1.0 (dark) → 3.0+ (bright daylight). Adjusts element visibility.
    @Published var uiBrightnessBoost: Double = 1.0
    /// True when the front camera reports bright daylight — the torch stays off
    /// and the UI is brightened for visibility in sunlight.
    @Published var isDaylight: Bool = false
    @Published var lunarDateStr: String = ""
    @Published var gregorianDateStr: String = ""
    @Published var factorCards: [FactorCardData] = []
    @Published var moonCard: MoonCardData = MoonCardData(
        phaseName: "...", brightnessDelta: 0, isActive: true)
    @Published var weatherCard: WeatherCardData = WeatherCardData(
        condition: "...", brightnessDelta: 0, isActive: true, provider: .none)
    @Published var showArrivalSummary: Bool = false
    /// Latest Health sync state for the arriving session (nil = no status shown).
    @Published var healthSyncStatus: String?
    @Published private(set) var currentWalkSession: WalkSession?
    /// Current moon phase image filename (e.g. "full_moon") for corner decoration
    @Published var currentMoonPhaseName: String = "full_moon"

    private var lastStepCount: Int = 0
    /// Smoothed step cadence (0 = still, ~2 = brisk walk). Drives rhythm pulse in glow.
    @Published var cadence: Double = 0
    private var cadenceDeltas: [Int] = []

    let lightEngine = LightEngine()
    private let healthSyncService = HealthSyncService(
        store: HealthKitStore(),
        context: PersistenceController.shared.container.viewContext)
    /// Spike: closed-loop torch controller. Setpoint 0.4 is the fixed spike
    /// target on the normalized 0–1 ROI scale (see the startup probe below);
    /// weather/dark-adaptation modifiers plug in later.
    private var torchController = TorchController(
        levels: [0, 0.15, 0.3, 0.45, 0.6, 0.75, 0.9, 1.0],
        deadband: 0.04, hysteresis: 0.02)
    /// Startup probe: with the back exposure locked, the raw ROI is ~1e-4 and
    /// an absolute setpoint of 0.4 is unreachable — the controller would ramp
    /// to 100% the moment the posture gate activates. Once per walk, pin the
    /// torch at torchProbeLevel for a few ticks, record the torch-off floor and
    /// torch-on ceiling, then control on the normalized [0,1] scale where 0.4
    /// means "40% of the torch's full contribution".
    private enum TorchProbeState { case idle, floorProbe, ceilingProbe, calibrated }
    private var torchProbeState: TorchProbeState = .idle
    private var torchProbeTicks = 0
    private var torchCalibration: (floor: Double, ceiling: Double)?
    private let torchProbeLevel = 0.9
    private let torchFloorTicksNeeded = 1
    private let torchCeilingTicksNeeded = 3
    private let torchSetpoint = 0.4
    /// Whether the controller has been seeded for this walk.
    private var torchSeeded = false
    private var loggedBackFallback = false
    let sensorManager = SensorManager()
    let weatherService = WeatherService()
    let locationManager = LocationManager()

    var sensorTimer: Timer?
    private var hasStarted = false

    // MARK: - Start Walk

    func startWalk() {
        guard !hasStarted else { return }
        hasStarted = true
        isActive = true
        walkClock.resume()
        Log.debug("[Walk] startWalk — initial ambient=\(sensorManager.ambientLightLevel), brightness=\(brightness)")

        // Reset the startup probe for this walk. Seeding happens on the first
        // closed-loop tick, from the front-camera ambient level.
        torchSeeded = false
        torchProbeState = .idle
        torchProbeTicks = 0
        torchCalibration = nil

        // Prevent screen sleep and auto-dim during walk
        UIApplication.shared.isIdleTimerDisabled = true
        // Remember the user's screen brightness so it can be handed back when
        // the walk ends — the app takes over screen brightness during the walk.
        originalScreenBrightness = UIScreen.main.brightness

        sensorManager.start()
        // Screen brightness follows ambient at the sensor's sample rate (2Hz)
        // instead of the 1s tick, so it responds to light changes immediately.
        sensorManager.onAmbientUpdate = { [weak self] in
            self?.updateScreenBrightness()
        }

        let context = PersistenceController.shared.container.viewContext
        let moon = MoonPhase.current()
        currentMoonPhaseName = moon.phase
        // Set initial moon card immediately, don't wait for first tick
        moonCard = MoonCardData(
            phaseName: L10n.moonPhaseName(illumination: moon.illumination),
            brightnessDelta: 0,
            isActive: true
        )
        currentWalkSession = WalkSession.create(
            in: context, moonPhase: moon.phase,
            weatherCondition: weatherService.currentCondition
        )
        PersistenceController.shared.save()

        locationManager.startRecording(session: currentWalkSession!)

        // Weather fetch — try immediately, retry up to 2 more times with 5s delay
        Task { [weak self] in
            for i in 0..<3 {
                guard let self = self, self.isActive else { return }
                if i > 0 { try? await Task.sleep(nanoseconds: 5_000_000_000) }
                if let loc = self.locationManager.currentLocation {
                    await self.weatherService.fetch(at: loc)
                    if self.weatherService.currentCondition != nil { break }
                }
            }
        }

        startSensorLoop()
    }

    // MARK: - Sensor Loop

    private var sensorTick: Int = 0
    private var cachedMoonPhase: (phase: String, illumination: Double)?
    private var lastMoonUpdateTick: Int = -60  // force first compute
    /// Weather auto-retry: the start-of-walk attempts can all fail (cold
    /// start, airplane mode), which would otherwise leave the weather factor
    /// off for the whole walk. Re-attempt every 5 minutes while it's missing.
    private var weatherRetryTick = 0
    private var isFetchingWeather = false

    private func startSensorLoop() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        // Timer's block is @Sendable, so hop to MainActor explicitly. (The
        // "unsafeForcedSync called from Swift Concurrent context" log is
        // unrelated noise from the system AXCoreUtilities framework; it also
        // appears in an empty project and cannot be silenced from app code.)
        sensorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func tick() {
        guard isActive, !isPaused else { return }
        sensorTick += 1
        updateBatteryState()

        // Cache moon phase — update once per 60 ticks
        if sensorTick - lastMoonUpdateTick >= 60 {
            let moon = MoonPhase.current()
            cachedMoonPhase = (moon.phase, moon.illumination)
            lastMoonUpdateTick = sensorTick
        }
        let (_, moonIllum) = cachedMoonPhase ?? ("full_moon", 0.5)

        // Effective daylight: the debounced detector state, suppressed while the
        // proximity sensor reports occlusion. Computed before the snapshot so the
        // LightEngine gate and the UI (notice bar, screen brightness) consume the
        // exact same value.
        isDaylight = !sensorManager.isOccluded && sensorManager.isDaylight

        let snap = SensorSnapshot(
            ambientLight: sensorManager.ambientLightLevel,
            devicePitch: sensorManager.devicePitch,
            deviceRoll: sensorManager.deviceRoll,
            moonIllumination: moonIllum,
            weather: weatherService.currentCondition,
            darkAdaptationMinutes: walkClock.elapsed() / 60.0,
            isDaylight: isDaylight
        )
        // The model (and its factor attribution) must stay fresh every tick —
        // even while the closed loop controls the actual torch level — so the
        // moon/weather names and the factor deductions match the displayed
        // brightness. Previously it was only updated in the fallback path,
        // leaving the factor cards stale (names empty, deductions ~0).
        lightEngine.update(sensors: snap)
        if sensorManager.isOccluded && !isTorchOccluded {
            isTorchOccluded = true
            sensorManager.setTorchLevel(0)
        } else if !sensorManager.isOccluded && isTorchOccluded {
            isTorchOccluded = false
        }
        cameraDeniedForAmbient = AVCaptureDevice.authorizationStatus(for: .video) == .denied
        let gate = LoopGate(pitchDeg: sensorManager.devicePitch,
                            isOccluded: sensorManager.isOccluded,
                            isDaylight: isDaylight)
        if FeatureFlags.torchClosedLoop {
            // 后摄只在闭环真正控制手电（走路姿势、未遮挡、非白天、非手动）
            // 时才需要；其余时间停掉第二路 ISP 以降低发热。
            sensorManager.setBackCameraEnabled(gate.isActive && !lightEngine.isManual)
        }
        if FeatureFlags.torchClosedLoop, sensorManager.backGroundLuminance == nil, !loggedBackFallback {
            loggedBackFallback = true
            Log.debug("[Loop] backGroundLuminance nil — closed loop inactive, LightEngine fallback")
        }
        usesClosedLoop = FeatureFlags.torchClosedLoop && sensorManager.backGroundLuminance != nil && !lightEngine.isManual
        if lightEngine.isManual {
            // 手动模式：所有自动调整机制关闭，亮度 = 手动值。
            // 仅遮挡仍优先关灯（安全），白天门控与因子模型都让位。
            if sensorManager.isOccluded {
                brightness = 0
            } else {
                brightness = thermallyCapped(lightEngine.targetBrightness)
            }
            sensorManager.setTorchLevel(brightness)
            locationManager.currentTorchBrightness = brightness
        } else if FeatureFlags.torchClosedLoop, let y = sensorManager.backGroundLuminance {
            // 闭环接管手电；遮挡/白天按全局约束优先关灯。
            if sensorManager.isOccluded || isDaylight {
                brightness = 0
            } else {
                brightness = min(max(thermallyCapped(min(closedLoopBrightness(measured: y, gate: gate), lightEngine.batterySaverCap)),
                                     0.05), 1.0)
            }
            sensorManager.setTorchLevel(brightness)
            locationManager.currentTorchBrightness = brightness
        } else if !isTorchOccluded {
            brightness = thermallyCapped(lightEngine.targetBrightness)
            sensorManager.setTorchLevel(brightness)
            locationManager.currentTorchBrightness = brightness
        }
        let thermal = ProcessInfo.processInfo.thermalState
        isThermalNoticeVisible = (thermal == .serious || thermal == .critical)
            && brightness > 0.05

        weatherRetryTick += 1
        if weatherRetryTick % 300 == 0 {
            retryWeatherIfNeeded()
        }
        stepCount = completedSteps + sensorManager.stepCount
        let dist = locationManager.totalDistance

        let isActuallyMoving = stepCount > lastStepCount
        if isActuallyMoving {
            displayDistance = dist
        }
        lastStepCount = stepCount

        // Cadence: steps/second over a 3-tick rolling window, smoothed
        let stepDelta = isActuallyMoving ? 1 : 0
        cadenceDeltas.append(stepDelta)
        if cadenceDeltas.count > 3 { cadenceDeltas.removeFirst() }
        let rawCadence = Double(cadenceDeltas.reduce(0, +)) / 3.0
        cadence = cadence * 0.7 + rawCadence * 0.3

        currentHeading = locationManager.currentHeading?.trueHeading ?? 0
        locationManager.externalStepCount = sensorManager.stepCount
        // Feed real sensor values so recorded path points carry true ambient
        // light and torch brightness (torch drives the constellation coloring).
        locationManager.currentAmbientLight = sensorManager.ambientLightLevel
        locationManager.currentTorchBrightness = brightness
        locationManager.updateDeadReckoning(
            stepCount: sensorManager.stepCount,
            heading: currentHeading
        )
        let ambient = sensorManager.ambientLightLevel
        // In bright daylight push the UI to full brightness so it stays readable.
        uiBrightnessBoost = isDaylight ? 3.5 : (1.0 + ambient * 2.0)
        updateScreenBrightness()
        lunarDateStr = LunarDate.display()
        gregorianDateStr = LunarDate.gregorianShort()
        gpsActive = locationManager.isRecording &&
            (locationManager.authorizationStatus == .authorizedWhenInUse ||
             locationManager.authorizationStatus == .authorizedAlways)
        gpsAccuracyMeters = locationManager.isRecording
            ? locationManager.currentLocation?.horizontalAccuracy
            : nil
        pathPoints = currentWalkSession?.pathPointsArray ?? []
        elapsedMinutes = Int(walkClock.elapsed() / 60)

        let d = lightEngine.factorDetails
        let phaseName = d.moonPhaseName.isEmpty ? "..." : d.moonPhaseName
        // The five factors' deductions are rescaled to the ACTUAL brightness
        // gap so the HUD reconciles: brightness + sum(deductions) = 100%. The
        // share proportions come from the model's fresh shortfall attribution.
        let gap = max(0.0, 1.0 - brightness)
        let shareSum = d.ambientShare + d.postureShare + d.darkShare
                     + d.moonShare + d.weatherShare
        func deduction(_ share: Double) -> Int {
            guard shareSum > 0.0001, gap > 0.001 else { return 0 }
            return -Int((share / shareSum * gap * 100).rounded())
        }
        moonCard = MoonCardData(
            phaseName: phaseName,
            brightnessDelta: deduction(d.moonShare),
            isActive: lightEngine.moonFactorActive
        )
        let hasWeather = weatherService.currentCondition != nil
        weatherCard = WeatherCardData(
            condition: hasWeather ? d.weatherCondition : "...",
            brightnessDelta: deduction(d.weatherShare),
            isActive: lightEngine.weatherFactorActive,
            provider: weatherService.provider
        )
        factorCards = [
            FactorCardData(id: "ambient", icon: "eye.fill",
                label: L10n.factorAmbient,
                brightnessDelta: deduction(d.ambientShare),
                isActive: lightEngine.ambientFactorActive),
            FactorCardData(id: "posture", icon: "iphone",
                label: L10n.factorPosture,
                brightnessDelta: deduction(d.postureShare),
                isActive: lightEngine.postureFactorActive),
            FactorCardData(id: "dark", icon: "moon.zzz.fill",
                label: L10n.factorDark,
                brightnessDelta: deduction(d.darkShare),
                isActive: lightEngine.darkAdaptationActive),
        ]

        let displayDist = displayDistance
        if displayDist < 1000 {
            elapsedDistance = String(format: L10n.hudDistanceMeters, displayDist)
        } else {
            elapsedDistance = String(format: L10n.hudDistanceKm, displayDist / 1000)
        }

        // Batch Core Data saves: every 5 ticks instead of every second
        if sensorTick % 5 == 0 {
            checkpoint()
        }
    }

    // MARK: - Weather Auto-Retry

    /// Re-attempt the weather fetch mid-walk when it failed at start. The
    /// 5-minute cadence is cheap (one request), and a nil condition would
    /// otherwise silently disable the weather factor for the whole walk.
    private func retryWeatherIfNeeded() {
        guard !isFetchingWeather,
              weatherService.currentCondition == nil,
              let loc = locationManager.currentLocation else { return }
        isFetchingWeather = true
        Task { [weak self] in
            defer { self?.isFetchingWeather = false }
            await self?.weatherService.fetch(at: loc)
        }
    }

    // MARK: - Torch Closed Loop (spike)

    private func closedLoopBrightness(measured y: Double, gate: LoopGate) -> Double {
        if !torchSeeded {
            torchSeeded = true
            // Seed at the ambient-implied level: dark scene → high torch,
            // bright scene → low. The debounced bright-scene latch (isDaylight)
            // and the ambient fallback below take over the bright-room case.
            torchController.seed(level: max(0.0, 1.0 - sensorManager.ambientLightLevel))
        }
        if gate.isActive {
            if torchProbeState != .calibrated {
                advanceTorchProbe(measured: y)
                // The tick that completes the probe hands off to the controller
                // so it can react to the freshly measured ceiling immediately.
                if torchProbeState == .calibrated {
                    return torchController.step(setpoint: torchSetpoint,
                                                measured: normalizedBackLuminance(y),
                                                active: true)
                }
                return torchProbePin
            }
            return torchController.step(setpoint: torchSetpoint,
                                        measured: normalizedBackLuminance(y),
                                        active: true)
        }
        // Not in walking posture: the back camera isn't looking at the ground
        // the torch would illuminate (it may face the ceiling or sky), so the
        // front-camera ambient decides — bright scene → torch off, dark scene
        // → torch on. The back camera only fine-tunes the level while the loop
        // is active.
        return max(0.0, 1.0 - sensorManager.ambientLightLevel)
    }

    private var torchProbePin: Double {
        switch torchProbeState {
        case .floorProbe: return 0
        case .ceilingProbe: return torchProbeLevel
        default: return 0
        }
    }

    /// Map the exposure-locked ROI onto the [0,1] scale measured by the startup
    /// probe: 0 = torch-off floor, 1 = torch-on ceiling.
    private func normalizedBackLuminance(_ y: Double) -> Double {
        guard let cal = torchCalibration, cal.ceiling > cal.floor else { return 0 }
        return min(max((y - cal.floor) / (cal.ceiling - cal.floor), 0), 1)
    }

    /// Advance the startup probe one tick. Pins the torch at torchProbeLevel
    /// until torchCeilingTicksNeeded torch-on samples are collected, then marks
    /// the loop calibrated. A torch-off floor phase runs first so the [floor,
    /// ceiling] range is measured at torch 0 / torch 0.9 regardless of what
    /// level the torch had when the gate activated.
    private func advanceTorchProbe(measured y: Double) {
        switch torchProbeState {
        case .idle:
            torchProbeState = .floorProbe
            torchProbeTicks = 0
            torchCalibration = (floor: y, ceiling: y)
        case .floorProbe:
            if let cal = torchCalibration {
                torchCalibration = (floor: min(cal.floor, y), ceiling: cal.ceiling)
            }
            torchProbeTicks += 1
            if torchProbeTicks >= torchFloorTicksNeeded {
                torchProbeState = .ceilingProbe
                torchProbeTicks = 0
            }
        case .ceilingProbe:
            if let cal = torchCalibration {
                torchCalibration = (floor: cal.floor, ceiling: max(cal.ceiling, y))
            }
            torchProbeTicks += 1
            if torchProbeTicks >= torchCeilingTicksNeeded {
                torchProbeState = .calibrated
                if let cal = torchCalibration {
                    Log.debug("[Loop] calibrated floor=\(cal.floor) ceiling=\(cal.ceiling) range=\(cal.ceiling - cal.floor)")
                }
            }
        case .calibrated:
            break
        }
    }

    // MARK: - End Walk

    func pauseWalk() {
        guard isActive, !isPaused else { return }
        walkClock.pause()
        checkpoint()
        completedSteps = stepCount
        isPaused = true
        sensorManager.onAmbientUpdate = nil
        sensorManager.stop()
        locationManager.stopRecording()
        sensorTimer?.invalidate()
        brightness = 0
        cadence = 0
        isTorchOccluded = false
        isThermalNoticeVisible = false
        gpsActive = false
        UIApplication.shared.isIdleTimerDisabled = false
        restoreScreenBrightness()
    }

    func resumeWalk() {
        guard isActive, isPaused, let session = currentWalkSession else { return }
        isPaused = false
        walkClock.resume()
        originalScreenBrightness = UIScreen.main.brightness
        UIApplication.shared.isIdleTimerDisabled = true
        torchSeeded = false
        torchProbeState = .idle
        torchCalibration = nil
        lastStepCount = completedSteps
        cadenceDeltas = []
        sensorManager.start()
        sensorManager.onAmbientUpdate = { [weak self] in self?.updateScreenBrightness() }
        locationManager.startRecording(session: session)
        startSensorLoop()
        tick()
    }

    private func checkpoint() {
        guard let session = currentWalkSession else { return }
        // While paused the last sensor reading has already been accumulated.
        stepCount = isPaused ? completedSteps : completedSteps + sensorManager.stepCount
        session.totalSteps = Int64(stepCount)
        session.totalDistance = locationManager.totalDistance
        session.activeDuration = NSNumber(value: walkClock.elapsed())
        session.lastCheckpoint = Date()
        let points = session.pathPointsArray
        if !points.isEmpty {
            session.avgLightLevel = points.reduce(0) { $0 + $1.ambientLight } / Double(points.count)
        }
        session.weatherCondition = weatherService.currentCondition
        PersistenceController.shared.save()
    }

    func discardZeroStepWalk() {
        finishWalk(showPoster: false, discard: true)
    }

    func endWalkAndNotify() { finishWalk(showPoster: true) }
    func endWalkAbruptly() { finishWalk(showPoster: false) }

    private func finishWalk(showPoster: Bool, discard: Bool = false) {
        guard isActive else { return }
        if !isPaused { pauseWalk() }
        isActive = false
        guard let session = currentWalkSession else { return }
        session.endTime = Date()
        guard !discard, session.isCompleteRecord else {
            PersistenceController.shared.container.viewContext.delete(session)
            PersistenceController.shared.save()
            showArrivalSummary = false
            return
        }
        session.endType = showPoster ? "completed" : "interrupted"
        session.healthSyncState = HealthSyncState.pending.rawValue
        PersistenceController.shared.save()
        Task {
            healthSyncStatus = HealthSyncState.pending.rawValue
            await healthSyncService.sync(session: session)
            healthSyncStatus = session.healthSyncState
        }
        showArrivalSummary = showPoster
    }

    // MARK: - Toggles

    func toggleFactor(id: String) {
        switch id {
        case "ambient": lightEngine.toggleAmbientFactor()
        case "posture": lightEngine.togglePostureFactor()
        case "dark":    lightEngine.toggleDarkFactor()
        case "moon":    lightEngine.toggleMoonFactor()
        case "weather": lightEngine.toggleWeatherFactor()
        default: break
        }
        Haptic.selection()
    }
    func setManualBrightness(_ level: Double) {
        guard isActive, !isPaused else { return }
        // 允许 0：手动模式可把闪光灯完全关闭。
        let snapped = min(max((level * 10).rounded() / 10, 0.0), 1.0)
        // Immediate, discrete feedback during the drag — don't wait for the 1s
        // tick to recompute brightness. Snap to 10% steps so the HUD ring
        // advances one segment at a time and the torch follows the finger.
        lightEngine.setManualBrightness(snapped)
        brightness = thermallyCapped(snapped)
        sensorManager.setTorchLevel(brightness)
        locationManager.currentTorchBrightness = brightness
    }
    func resetToAutoBrightness() { lightEngine.resetManualBrightness() }

    /// 热状态降档后的手电亮度：serious ≤ 0.6，critical ≤ 0.3。
    private func thermallyCapped(_ level: Double) -> Double {
        TorchThermalPolicy.cappedLevel(level, thermalState: ProcessInfo.processInfo.thermalState)
    }

    // MARK: - GPS Signal Quality (HUD indicator)

    /// "±12m" readout for the HUD, nil when no fix is available.
    var gpsAccuracyLabel: String? {
        guard let acc = gpsAccuracyMeters, acc > 0 else { return nil }
        return "±\(Int(acc))m"
    }

    /// Color-codes GPS fix quality: green (accurate ≤15m), yellow (marginal
    /// ≤50m), red (weak or no fix). Path points are recorded only when
    /// accuracy < 30m, so red/yellow means drawing lags behind the step count.
    var gpsQualityColor: Color {
        guard let acc = gpsAccuracyMeters, acc > 0 else { return .red.opacity(0.35) }
        if acc <= 15 { return .green.opacity(0.6) }
        if acc <= 50 { return .yellow.opacity(0.7) }
        return .red.opacity(0.6)
    }

    // MARK: - Screen Brightness (daylight boost / pocket dim)

    private var originalScreenBrightness: CGFloat?

    /// Whether the torch was actually on when occlusion set in — the "torch off
    /// in pocket" notice and the pocket screen-dim share this truth, so the
    /// notice never claims a pocket torch-off when the torch was off for another
    /// reason (paused or daylight).
    var occlusionNoticeVisible: Bool {
        isTorchOccluded && !isDaylight && brightness > 0
    }

    /// Factor shortfall proportions (ambient/posture/dark/moon/weather),
    /// normalized to sum 1 — colors the unfilled progress-line segments that
    /// the factors "deduct" from the brightness.
    var factorShares: [Double] {
        guard !usesClosedLoop, !lightEngine.isManual else { return [0, 0, 0, 0, 0] }
        let d = lightEngine.factorDetails
        let sum = d.ambientShare + d.postureShare + d.darkShare
                + d.moonShare + d.weatherShare
        guard sum > 0.0001 else { return [0, 0, 0, 0, 0] }
        return [d.ambientShare / sum, d.postureShare / sum,
                d.darkShare / sum, d.moonShare / sum, d.weatherShare / sum]
    }

    /// Screen brightness is ambient-continuous and immediate (no debounce —
    /// unlike the torch, which deliberately ramps slowly for safety):
    /// 1. Pocket — occluded AND the torch was on → dim to 0 to save battery.
    /// 2. Bright daylight → 1.0 so the UI is readable against the sun.
    /// 3. Otherwise → 0.25 + 0.75 × ambient (dark room dims the screen, a
    ///    bright room brightens it, within one tick of the ambient changing).
    private func updateScreenBrightness() {
        guard isActive, !isPaused else {
            // Not walking — always hand the user's brightness back. A walk may
            // have ended while dimmed/boosted, and the sensor loop that would
            // have restored it has stopped.
            restoreScreenBrightness()
            return
        }
        let desired: Double
        if occlusionNoticeVisible {
            desired = 0
        } else if isDaylight {
            desired = 1.0
        } else {
            let ambient = sensorManager.ambientLightLevel
            desired = min(1.0, max(0.25, 0.25 + 0.75 * ambient))
        }
        // Quantize to the same 10% steps as the HUD bar, so the screen and the
        // indicator always agree and sub-segment EMA jitter can't strobe the
        // screen with tiny writes (the flicker reported on device).
        let quantized = (desired * 10).rounded() / 10
        screenBrightness = quantized
        if abs(UIScreen.main.brightness - CGFloat(quantized)) > 0.005 {
            UIScreen.main.brightness = CGFloat(quantized)
        }
    }

    /// Restore the user's screen brightness (backgrounding).
    private func restoreScreenBrightness() {
        guard let orig = originalScreenBrightness else { return }
        UIScreen.main.brightness = orig
        originalScreenBrightness = nil
    }

    func didEnterBackground() {
        pauseWalk()
    }

    // MARK: - Private

    private func updateBatteryState() {
        let level = UIDevice.current.batteryLevel
        batteryPercentage = level >= 0 ? Int(level * 100) : -1
        let charging = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
        if charging || batteryPercentage < 0 {
            lightEngine.batterySaverCap = 1
        } else if batteryPercentage <= 10 {
            lightEngine.batterySaverCap = 0.6
        } else if batteryPercentage <= 20 {
            lightEngine.batterySaverCap = 0.8
        } else {
            lightEngine.batterySaverCap = 1
        }
    }

}

// MARK: - Card Data Models

struct MoonCardData {
    let phaseName: String
    let brightnessDelta: Int
    let isActive: Bool
}

struct WeatherCardData {
    let condition: String
    let brightnessDelta: Int
    let isActive: Bool
    let provider: WeatherService.Provider
}

struct FactorCardData: Identifiable {
    let id: String          // "ambient", "posture", "dark", "moon", "weather"
    let icon: String        // SF Symbol name
    let label: String       // factor name
    let brightnessDelta: Int
    let isActive: Bool
}
