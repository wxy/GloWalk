import SwiftUI
import CoreLocation

@MainActor
final class HUDViewModel: ObservableObject {
    @Published var brightness: Double = 0.7
    @Published var isActive: Bool = false
    @Published var elapsedDistance: String = "0.0km"
    @Published var estimatedMinutesRemaining: Int = 0
    @Published var batteryPercentage: Int = 100
    @Published var stepCount: Int = 0
    @Published var moonCard: MoonCardData?
    @Published var weatherCard: WeatherCardData?
    @Published var showArrivalSummary: Bool = false
    @Published var generatedPosterImage: UIImage?
    @Published private(set) var currentWalkSession: WalkSession?

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

        if let loc = locationManager.currentLocation {
            Task { await weatherService.fetch(at: loc) }
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
                self.lightEngine.update(sensors: snap)
                self.brightness = self.lightEngine.targetBrightness
                self.stepCount = self.sensorManager.stepCount

                let d = self.lightEngine.factorDetails
                self.moonCard = MoonCardData(
                    phaseName: d.moonPhaseName, effectPercent: d.moonEffectPercent,
                    isActive: self.lightEngine.moonFactorActive
                )
                if let w = self.weatherService.currentCondition {
                    self.weatherCard = WeatherCardData(
                        condition: d.weatherCondition, effectPercent: d.weatherEffectPercent,
                        isActive: self.lightEngine.weatherFactorActive
                    )
                }

                self.updateBatteryEstimate()
                self.elapsedDistance = String(format: "%.1fkm", self.locationManager.totalDistance / 1000)
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
    }
    func didBecomeActive() {
        enteredBackground = false
        brightness = lightEngine.targetBrightness
    }

    // MARK: - Private

    private func updateBatteryEstimate() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        batteryPercentage = Int(UIDevice.current.batteryLevel * 100)
        let base = 240.0
        let bf = 1.0 / max(brightness, 0.1)
        let bat = Double(batteryPercentage) / 100.0
        estimatedMinutesRemaining = Int(base * bf * bat)
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
