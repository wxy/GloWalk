import SwiftUI
import CoreLocation

@MainActor
final class HUDViewModel: ObservableObject {
    @Published var brightness: Double = 0.7
    @Published var isActive: Bool = false
    @Published var elapsedDistance: String = "0m"
    private var displayDistance: Double = 0
    @Published var elapsedMinutes: Int = 0
    @Published var estimatedMinutesRemaining: Int = 90
    @Published var batteryPercentage: Int = 100
    @Published var stepCount: Int = 0
    @Published var isTorchOccluded: Bool = false
    @Published var pathPoints: [PathPoint] = []
    @Published var gpsActive: Bool = false
    @Published var currentHeading: Double = 0
    /// UI brightness boost factor: 1.0 (dark) → 2.5 (bright daylight). Adjusts element visibility.
    @Published var uiBrightnessBoost: Double = 1.0
    @Published var placeName: String = ""
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
    private var lastDistance: Double = 0
    private var lastStepCount: Int = 0
    /// Smoothed step cadence (0 = still, ~2 = brisk walk). Drives rhythm pulse in glow.
    @Published var cadence: Double = 0
    private var cadenceDeltas: [Int] = []

    let lightEngine = LightEngine()
    let sensorManager = SensorManager()
    let weatherService = WeatherService()
    let locationManager = LocationManager()

    private var sessionStartTime: Date?
    var sensorTimer: Timer?
    private var hasStarted = false

    // MARK: - Start Walk

    func startWalk(isQuickLaunch: Bool = false) {
        guard !hasStarted else { return }
        hasStarted = true
        isActive = true
        sessionStartTime = Date()

        // Prevent screen sleep and auto-dim during walk
        UIApplication.shared.isIdleTimerDisabled = true

        sensorManager.start()

        let context = PersistenceController.shared.container.viewContext
        let moon = MoonPhase.current()
        currentMoonPhaseName = moon.phase
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
        sensorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            MainActor.assumeIsolated {
                self.tick()
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

        let snap = SensorSnapshot(
            ambientLight: sensorManager.ambientLightLevel,
            devicePitch: sensorManager.devicePitch,
            deviceRoll: sensorManager.deviceRoll,
            screenBrightness: UIScreen.main.brightness,
            isWalking: sensorManager.isWalking,
            moonIllumination: moonIllum,
            weather: weatherService.currentCondition,
            darkAdaptationMinutes: Date().timeIntervalSince(sessionStartTime ?? Date()) / 60.0
        )
        if sensorManager.isOccluded && !isTorchOccluded {
            isTorchOccluded = true
            sensorManager.setTorchLevel(0)
        } else if !sensorManager.isOccluded && isTorchOccluded {
            isTorchOccluded = false
        }
        if !isTorchOccluded {
            lightEngine.update(sensors: snap)
            brightness = lightEngine.targetBrightness
            sensorManager.setTorchLevel(brightness)
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
        locationManager.updateDeadReckoning(
            stepCount: sensorManager.stepCount,
            heading: currentHeading
        )
        let ambient = sensorManager.ambientLightLevel
        uiBrightnessBoost = 1.0 + ambient * 2.0
        placeName = locationManager.placeName ?? ""
        lunarDateStr = LunarDate.display()
        gregorianDateStr = LunarDate.gregorianShort()
        gpsActive = locationManager.isRecording &&
            (locationManager.authorizationStatus == .authorizedWhenInUse ||
             locationManager.authorizationStatus == .authorizedAlways)
        pathPoints = currentWalkSession?.pathPointsArray ?? []
        elapsedMinutes = Int(activeWalkSeconds / 60)

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
                label: L10n.isZh ? "环境光" : "Ambient",
                brightnessDelta: d.ambientDelta,
                isActive: lightEngine.ambientFactorActive),
            FactorCardData(id: "posture", icon: "iphone",
                label: L10n.isZh ? "姿态" : "Posture",
                brightnessDelta: d.postureDelta,
                isActive: lightEngine.postureFactorActive),
            FactorCardData(id: "screen", icon: "sun.max.fill",
                label: L10n.isZh ? "屏幕" : "Screen",
                brightnessDelta: d.screenDelta,
                isActive: lightEngine.screenFactorActive),
            FactorCardData(id: "dark", icon: "moon.zzz.fill",
                label: L10n.isZh ? "暗适应" : "Adapt",
                brightnessDelta: d.darkDelta,
                isActive: lightEngine.darkAdaptationActive),
        ]

        updateBatteryEstimate()
        let displayDist = displayDistance
        if displayDist < 1000 {
            elapsedDistance = String(format: "%.0fm", displayDist)
        } else {
            elapsedDistance = String(format: "%.1fkm", displayDist / 1000)
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
        sensorManager.stop()
        locationManager.stopRecording()
        sensorTimer?.invalidate()

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
        sensorManager.stop()
        locationManager.stopRecording()
        sensorTimer?.invalidate()
        if let s = currentWalkSession {
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
        case "screen":  lightEngine.toggleScreenFactor()
        case "dark":    lightEngine.toggleDarkFactor()
        case "moon":    lightEngine.toggleMoonFactor()
        case "weather": lightEngine.toggleWeatherFactor()
        default: break
        }
    }
    func toggleMoonFactor() { lightEngine.toggleMoonFactor() }
    func toggleWeatherFactor() { lightEngine.toggleWeatherFactor() }
    func setManualBrightness(_ level: Double) {
        lightEngine.setManualOffset(level - lightEngine.targetBrightness)
    }
    func resetToAutoBrightness() { lightEngine.resetManualOffset() }

    var enteredBackground = false
    func willResignActive() {
        enteredBackground = true
        UIApplication.shared.isIdleTimerDisabled = false
        lightEngine.enterSafetyFallback()
        sensorManager.setTorchLevel(1.0)
    }
    func didBecomeActive() {
        enteredBackground = false
        UIApplication.shared.isIdleTimerDisabled = true
        brightness = lightEngine.targetBrightness
    }

    // MARK: - Private

    private func updateBatteryEstimate() {
        let state = UIDevice.current.batteryState
        // Charging or full → unlimited
        if state == .charging || state == .full {
            batteryPercentage = 100
            estimatedMinutesRemaining = -1  // -1 means unlimited
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
    let id: String          // "ambient", "posture", "screen", "dark"
    let icon: String        // SF Symbol name
    let label: String       // factor name
    let brightnessDelta: Int
    let isActive: Bool
}
