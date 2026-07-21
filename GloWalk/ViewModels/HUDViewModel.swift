import SwiftUI
import CoreLocation

@MainActor
final class HUDViewModel: ObservableObject {
    @Published var brightness: Double = 0.7
    @Published var isActive: Bool = false
    @Published var elapsedDistance: String = "0m"
    @Published var elapsedMinutes: Int = 0
    @Published var estimatedMinutesRemaining: Int = 90
    @Published var batteryPercentage: Int = 100
    @Published var stepCount: Int = 0
    @Published var isTorchOccluded: Bool = false
    @Published var moonCard: MoonCardData?
    @Published var weatherCard: WeatherCardData?
    @Published var showArrivalSummary: Bool = false
    @Published var generatedPosterImage: UIImage?
    @Published private(set) var currentWalkSession: WalkSession?

    private var activeWalkSeconds: Double = 0
    private var lastDistance: Double = 0

    let lightEngine = LightEngine()
    let sensorManager = SensorManager()
    let weatherService = WeatherService()
    let locationManager = LocationManager()

    private var sessionStartTime: Date?
    private var sensorTimer: Timer?
    private var hasStarted = false

    // MARK: - Start Walk

    func startWalk(isQuickLaunch: Bool = false) {
        guard !hasStarted else { return }
        hasStarted = true
        isActive = true
        sessionStartTime = Date()

        sensorManager.start()

        let context = PersistenceController.shared.container.viewContext
        let moon = MoonPhase.current()
        currentWalkSession = WalkSession.create(
            in: context, moonPhase: moon.phase,
            weatherCondition: weatherService.currentCondition
        )
        PersistenceController.shared.save()

        locationManager.startRecording(session: currentWalkSession!)

        // Weather fetch — retry up to 5 times with 5s intervals
        Task { [weak self] in
            for i in 0..<5 {
                guard let self = self, self.isActive else { return }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if let loc = self.locationManager.currentLocation {
                    print("[GloWalk] Weather attempt \(i+1): location available, fetching...")
                    await self.weatherService.fetch(at: loc)
                    if let cond = self.weatherService.currentCondition {
                        print("[GloWalk] Weather fetched: \(cond)")
                        break
                    } else {
                        print("[GloWalk] Weather fetch returned nil")
                    }
                } else {
                    print("[GloWalk] Weather attempt \(i+1): location still nil")
                }
            }
        }

        startSensorLoop()
    }

    // MARK: - Sensor Loop

    private func startSensorLoop() {
        sensorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isActive else { return }
                let moon = MoonPhase.current()
                let snap = SensorSnapshot(
                    ambientLight: self.sensorManager.ambientLightLevel,
                    devicePitch: self.sensorManager.devicePitch,
                    deviceRoll: self.sensorManager.deviceRoll,
                    screenBrightness: UIScreen.main.brightness,
                    isWalking: self.sensorManager.isWalking,
                    moonIllumination: moon.illumination,
                    weather: self.weatherService.currentCondition,
                    darkAdaptationMinutes: Date().timeIntervalSince(self.sessionStartTime ?? Date()) / 60.0
                )
                // Occlusion detection: turn off torch and flag UI
                if self.sensorManager.isOccluded && !self.isTorchOccluded {
                    self.isTorchOccluded = true
                    self.sensorManager.setTorchLevel(0)
                } else if !self.sensorManager.isOccluded && self.isTorchOccluded {
                    self.isTorchOccluded = false
                }
                if !self.isTorchOccluded {
                    self.lightEngine.update(sensors: snap)
                    self.brightness = self.lightEngine.targetBrightness
                    self.sensorManager.setTorchLevel(self.brightness)
                }
                self.stepCount = self.sensorManager.stepCount
                let dist = self.locationManager.totalDistance

                // Only count walking time when steps or distance are increasing
                if self.sensorManager.isWalking || dist > self.lastDistance {
                    self.activeWalkSeconds += 1
                }
                self.lastDistance = dist
                self.elapsedMinutes = Int(self.activeWalkSeconds / 60)

                let d = self.lightEngine.factorDetails
                self.moonCard = MoonCardData(
                    phaseName: d.moonPhaseName, effectPercent: d.moonEffectPercent,
                    isActive: self.lightEngine.moonFactorActive
                )
                if self.weatherService.currentCondition != nil {
                    self.weatherCard = WeatherCardData(
                        condition: d.weatherCondition, effectPercent: d.weatherEffectPercent,
                        isActive: self.lightEngine.weatherFactorActive
                    )
                }

                self.updateBatteryEstimate()
                if dist < 1000 {
                    self.elapsedDistance = String(format: "%.0fm", dist)
                } else {
                    self.elapsedDistance = String(format: "%.1fkm", dist / 1000)
                }
            }
        }
    }

    // MARK: - End Walk

    func endWalkAndNotify() {
        isActive = false
        sensorManager.stop()
        locationManager.stopRecording()
        sensorTimer?.invalidate()

        if let s = currentWalkSession {
            s.endTime = Date()
            s.endType = "completed"
            s.totalSteps = Int64(sensorManager.stepCount)
            s.totalDistance = locationManager.totalDistance
            s.avgLightLevel = sensorManager.ambientLightLevel
            PersistenceController.shared.save()
        }
        showArrivalSummary = true
    }

    func endWalkAbruptly() {
        isActive = false
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

    func toggleMoonFactor() { lightEngine.toggleMoonFactor() }
    func toggleWeatherFactor() { lightEngine.toggleWeatherFactor() }
    func setManualBrightness(_ level: Double) {
        lightEngine.setManualOffset(level - lightEngine.targetBrightness)
    }
    func resetToAutoBrightness() { lightEngine.resetManualOffset() }

    var enteredBackground = false
    func willResignActive() {
        enteredBackground = true
        lightEngine.enterSafetyFallback()
        sensorManager.setTorchLevel(1.0)
    }
    func didBecomeActive() {
        enteredBackground = false
        brightness = lightEngine.targetBrightness
    }

    // MARK: - Private

    private func updateBatteryEstimate() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        if level > 0 {
            batteryPercentage = Int(level * 100)
            // Base: ~90 min at 100% brightness on typical iPhone (conservative estimate)
            // Scale inversely with brightness: 50% bright → 2x runtime
            let base = 90.0
            let bf = 1.0 / max(brightness, 0.1)
            let bat = Double(batteryPercentage) / 100.0
            estimatedMinutesRemaining = Int(base * bf * bat)
        } else {
            batteryPercentage = 100
            estimatedMinutesRemaining = 90
        }
    }
}

// MARK: - Card Data Models

struct MoonCardData {
    let phaseName: String
    let effectPercent: Int
    let isActive: Bool
}

struct WeatherCardData {
    let condition: String
    let effectPercent: Int
    let isActive: Bool
}
