import SwiftUI
import AVFoundation
import CoreLocation

@MainActor
final class HUDViewModel: ObservableObject {
    @Published var brightness: Double = 0.7
    @Published var isActive: Bool = false
    @Published var elapsedDistance: String = String(format: L10n.hudDistanceMeters, 0)
    private var displayDistance: Double = 0
    @Published var elapsedMinutes: Int = 0
    @Published var estimatedMinutesRemaining: Int = 90
    @Published var batteryPercentage: Int = 100
    @Published var stepCount: Int = 0
    @Published var isTorchOccluded: Bool = false
    /// True when camera permission is denied — ambient light sensing unavailable.
    @Published var cameraDeniedForAmbient: Bool = false
    /// Long-press to temporarily turn off torch without ending walk
    @Published var torchPaused: Bool = false
    @Published var pathPoints: [PathPoint] = []
    @Published var gpsActive: Bool = false
    /// GPS fix accuracy in meters (CLLocation.horizontalAccuracy), nil when no
    /// fix is available. Drives the HUD signal-strength indicator — path points
    /// are only recorded when accuracy is < 30m, so a weak signal delays drawing.
    @Published var gpsAccuracyMeters: Double?
    @Published var currentHeading: Double = 0
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
    @Published private(set) var currentWalkSession: WalkSession?
    /// Current moon phase image filename (e.g. "full_moon") for corner decoration
    @Published var currentMoonPhaseName: String = "full_moon"

    private var activeWalkSeconds: Double = 0
    private var lastStepCount: Int = 0
    /// Smoothed step cadence (0 = still, ~2 = brisk walk). Drives rhythm pulse in glow.
    @Published var cadence: Double = 0
    private var cadenceDeltas: [Int] = []

    let lightEngine = LightEngine()
    /// Spike: closed-loop torch controller. Setpoint 0.4 is the fixed spike
    /// target; weather/dark-adaptation modifiers plug in later.
    private var torchController = TorchController(
        levels: [0, 0.15, 0.3, 0.45, 0.6, 0.75, 0.9, 1.0],
        deadband: 0.04, hysteresis: 0.02)
    let sensorManager = SensorManager()
    let weatherService = WeatherService()
    let locationManager = LocationManager()

    private var sessionStartTime: Date?
    var sensorTimer: Timer?
    private var hasStarted = false

    // MARK: - Start Walk

    func startWalk() {
        guard !hasStarted else { return }
        hasStarted = true
        isActive = true
        sessionStartTime = Date()
        print("[Walk] startWalk — initial ambient=\(sensorManager.ambientLightLevel), brightness=\(brightness)")

        // Prevent screen sleep and auto-dim during walk
        UIApplication.shared.isIdleTimerDisabled = true

        sensorManager.start()

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

    private func startSensorLoop() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        // Timer's block is @Sendable; hop to MainActor explicitly instead of
        // MainActor.assumeIsolated, which emits "unsafeForcedSync called from
        // Swift Concurrent context" because the runtime treats the block as a
        // concurrent context even though it fires on the main run loop.
        sensorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func tick() {
        guard isActive else { return }
        sensorTick += 1

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
            darkAdaptationMinutes: Date().timeIntervalSince(sessionStartTime ?? Date()) / 60.0,
            isDaylight: isDaylight
        )
        if sensorManager.isOccluded && !isTorchOccluded {
            isTorchOccluded = true
            sensorManager.setTorchLevel(0)
        } else if !sensorManager.isOccluded && isTorchOccluded {
            isTorchOccluded = false
        }
        cameraDeniedForAmbient = AVCaptureDevice.authorizationStatus(for: .video) == .denied
        if FeatureFlags.torchClosedLoop, let y = sensorManager.backGroundLuminance {
            let gate = LoopGate(pitchDeg: sensorManager.devicePitch,
                                isOccluded: sensorManager.isOccluded,
                                isDaylight: isDaylight,
                                isTorchPaused: torchPaused)
            // 闭环接管手电；遮挡/暂停/白天按全局约束优先关灯，闭环冻结值不得覆盖
            // （白天冻结在夜间最后一档会把手电亮着，必须强制归零）。
            if sensorManager.isOccluded || torchPaused || isDaylight {
                brightness = 0
            } else {
                brightness = torchController.step(setpoint: 0.4, measured: y, active: gate.isActive)
            }
            sensorManager.setTorchLevel(brightness)
            locationManager.currentTorchBrightness = brightness
            #if DEBUG
            // Device-campaign log line: filter "TLM" in Xcode Console.
            print("TLM," + TorchMeasurementLog.row(
                timestamp: Date(), torchLevel: brightness,
                fullFrame: sensorManager.backFullFrameLuminance ?? -1, roi: y,
                pitch: sensorManager.devicePitch, active: gate.isActive))
            #endif
        } else if !isTorchOccluded && !torchPaused {
            lightEngine.update(sensors: snap)
            brightness = lightEngine.targetBrightness
            sensorManager.setTorchLevel(brightness)
            locationManager.currentTorchBrightness = brightness
        } else if torchPaused {
            sensorManager.setTorchLevel(0)
            locationManager.currentTorchBrightness = 0
        }
        stepCount = sensorManager.stepCount
        let dist = locationManager.totalDistance

        let isActuallyMoving = stepCount > lastStepCount
        if isActuallyMoving {
            activeWalkSeconds += 1
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
        locationManager.externalStepCount = stepCount
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
        elapsedMinutes = Int(Date().timeIntervalSince(sessionStartTime ?? Date()) / 60)

        let d = lightEngine.factorDetails
        let phaseName = d.moonPhaseName.isEmpty ? "..." : d.moonPhaseName
        moonCard = MoonCardData(
            phaseName: phaseName,
            brightnessDelta: d.moonDelta,
            isActive: lightEngine.moonFactorActive
        )
        let hasWeather = weatherService.currentCondition != nil
        weatherCard = WeatherCardData(
            condition: hasWeather ? d.weatherCondition : "...",
            brightnessDelta: d.weatherDelta,
            isActive: lightEngine.weatherFactorActive,
            provider: weatherService.provider
        )
        factorCards = [
            FactorCardData(id: "ambient", icon: "eye.fill",
                label: L10n.factorAmbient,
                brightnessDelta: d.ambientDelta,
                isActive: lightEngine.ambientFactorActive),
            FactorCardData(id: "posture", icon: "iphone",
                label: L10n.factorPosture,
                brightnessDelta: d.postureDelta,
                isActive: lightEngine.postureFactorActive),
            FactorCardData(id: "dark", icon: "moon.zzz.fill",
                label: L10n.factorDark,
                brightnessDelta: d.darkDelta,
                isActive: lightEngine.darkAdaptationActive),
        ]

        updateBatteryEstimate()
        let displayDist = displayDistance
        if displayDist < 1000 {
            elapsedDistance = String(format: L10n.hudDistanceMeters, displayDist)
        } else {
            elapsedDistance = String(format: L10n.hudDistanceKm, displayDist / 1000)
        }

        // Batch Core Data saves: every 5 ticks instead of every second
        if sensorTick % 5 == 0 {
            PersistenceController.shared.save()
        }
    }

    // MARK: - End Walk

    func endWalkAndNotify() {
        isActive = false
        UIApplication.shared.isIdleTimerDisabled = false
        // Hand the user back their screen brightness before the sensor loop
        // stops — otherwise a walk that ends while dimmed (pocket) or boosted
        // (daylight) would leave the screen stuck at 0 or 1.0.
        restoreScreenBrightness()
        sensorManager.stop()
        locationManager.stopRecording()
        sensorTimer?.invalidate()
        print("[Walk] endWalk — steps=\(sensorManager.stepCount), distance=\(locationManager.totalDistance), ambient=\(sensorManager.ambientLightLevel)")

        if let s = currentWalkSession {
            s.endTime = Date()
            s.totalSteps = Int64(sensorManager.stepCount)
            s.totalDistance = locationManager.totalDistance
            s.avgLightLevel = sensorManager.ambientLightLevel
            // Don't save walks with zero steps
            if sensorManager.stepCount == 0 {
                PersistenceController.shared.container.viewContext.delete(s)
                PersistenceController.shared.save()
                showArrivalSummary = false
                return
            }
            s.endType = "completed"
            PersistenceController.shared.save()
        }
        showArrivalSummary = true
    }

    func endWalkAbruptly() {
        isActive = false
        UIApplication.shared.isIdleTimerDisabled = false
        // Same as endWalkAndNotify — never leave the screen dimmed/boosted.
        restoreScreenBrightness()
        sensorManager.stop()
        locationManager.stopRecording()
        sensorTimer?.invalidate()
        if let s = currentWalkSession {
            // Don't keep empty walks (consistent with endWalkAndNotify).
            if sensorManager.stepCount == 0 {
                PersistenceController.shared.container.viewContext.delete(s)
                PersistenceController.shared.save()
                return
            }
            s.endTime = Date()
            s.endType = "interrupted"
            s.totalSteps = Int64(sensorManager.stepCount)
            s.totalDistance = locationManager.totalDistance
            PersistenceController.shared.save()
        }
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
        lightEngine.setManualOffset(level - lightEngine.targetBrightness)
    }
    func resetToAutoBrightness() { lightEngine.resetManualOffset() }

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
        isTorchOccluded && !torchPaused && !isDaylight && brightness > 0
    }

    /// Screen brightness priority:
    /// 1. Pocket — occluded AND the torch was on → dim to 0 to save battery.
    /// 2. Bright daylight → boost to 1.0 so the UI is readable against the sun.
    /// 3. Otherwise → restore the user's brightness.
    ///
    /// The pocket dim only applies when the flashlight was actually on — if the
    /// torch is off (paused or daylight), occlusion must NOT black out the screen.
    private func updateScreenBrightness() {
        guard isActive else {
            // Not walking — always hand the user's brightness back. A walk may
            // have ended while dimmed/boosted, and the sensor loop that would
            // have restored it has stopped.
            restoreScreenBrightness()
            return
        }
        let desired: CGFloat?
        if occlusionNoticeVisible {
            if originalScreenBrightness == nil {
                originalScreenBrightness = UIScreen.main.brightness
            }
            desired = 0
        } else if isDaylight && !isTorchOccluded {
            if originalScreenBrightness == nil {
                originalScreenBrightness = UIScreen.main.brightness
            }
            desired = 1.0
        } else {
            desired = nil
        }
        if let desired {
            // Only write when the value actually changes — otherwise the 1s tick
            // would fight the user's Control Center brightness every second.
            if abs(UIScreen.main.brightness - desired) > 0.001 {
                UIScreen.main.brightness = desired
            }
        } else if let orig = originalScreenBrightness {
            UIScreen.main.brightness = orig
            originalScreenBrightness = nil
        }
    }

    /// Restore the user's screen brightness (backgrounding).
    private func restoreScreenBrightness() {
        guard let orig = originalScreenBrightness else { return }
        UIScreen.main.brightness = orig
        originalScreenBrightness = nil
    }

    var enteredBackground = false
    func willResignActive() {
        enteredBackground = true
        UIApplication.shared.isIdleTimerDisabled = false
        // Give the user back their screen brightness in the background.
        restoreScreenBrightness()
        // Let timer and GPS keep running — path points recorded in background
        // will naturally have torchBrightness=0 since iOS kills the flashlight.
    }
    func didBecomeActive() {
        guard enteredBackground else { return }
        enteredBackground = false
        UIApplication.shared.isIdleTimerDisabled = true
        // iOS stops the camera capture session while backgrounded — restart it
        // so the ambient-light factor keeps working after returning.
        sensorManager.resumeSessionIfNeeded()
        // Re-apply the screen-brightness state (daylight boost / pocket dim).
        updateScreenBrightness()
        brightness = lightEngine.targetBrightness
    }

    // MARK: - Private

    private func updateBatteryEstimate() {
        let state = UIDevice.current.batteryState
        // Charging or full → unlimited
        if state == .charging || state == .full {
            batteryPercentage = 100
            estimatedMinutesRemaining = -1  // -1 means unlimited
            // Clear any low-battery cap so the torch isn't dimmed the whole
            // time the phone is plugged in (the cap would otherwise only reset
            // on a non-charging tick).
            lightEngine.batterySaverCap = 1.0
            return
        }
        let level = UIDevice.current.batteryLevel
        if level > 0 {
            batteryPercentage = Int(level * 100)
            let base = 90.0
            let bf = 1.0 / max(brightness, 0.1)
            let bat = Double(batteryPercentage) / 100.0
            estimatedMinutesRemaining = Int(base * bf * bat)

            // Low-battery power saving: cap max brightness to extend runtime
            if batteryPercentage <= 10 {
                lightEngine.batterySaverCap = 0.6   // critical: max 60%
            } else if batteryPercentage <= 20 {
                lightEngine.batterySaverCap = 0.8   // warning: max 80%
            } else {
                lightEngine.batterySaverCap = 1.0   // normal: no cap
            }
        } else {
            batteryPercentage = 100
            estimatedMinutesRemaining = 90
            lightEngine.batterySaverCap = 1.0
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
