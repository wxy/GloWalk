import CoreLocation

@MainActor
final class LocationManager: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published var currentLocation: CLLocation?
    @Published var currentHeading: CLHeading?
    @Published var totalDistance: Double = 0
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isRecording: Bool = false

    private let manager = CLLocationManager()
    private var currentSession: WalkSession?
    private var lastRecordedCoord: CLLocationCoordinate2D?  // last valid GPS point saved to path
    private var lastStepCount: Int = 0
    private var lastGPSRecordedStepCount: Int = 0
    /// Throttle for Core Data commits: the HUD tick already saves every 5
    /// seconds in the foreground; this keeps background-recorded points
    /// durable too (timers don't fire in the background) without committing
    /// once per GPS/step point.
    private var lastBatchSave = Date.distantPast
    private var estimatedLat: Double?
    private var estimatedLon: Double?
    var externalStepCount: Int = 0  // set from HUDViewModel to gate GPS recording
    /// Real sensor values at recording time, injected each tick by HUDViewModel.
    var currentAmbientLight: Double = 0.5
    var currentTorchBrightness: Double = 0.7

    /// Maximum allowed deviation (degrees) between GPS bearing and device heading.
    /// Points exceeding this are treated as drift and filtered out.
    private let headingFilterThreshold: Double = 50

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 5
    }

    // MARK: - Pedestrian Dead Reckoning (indoor / no GPS)

    /// Commit inserted path points at most every 5 seconds.
    private func batchSaveIfDue() {
        let now = Date()
        guard now.timeIntervalSince(lastBatchSave) >= 5 else { return }
        lastBatchSave = now
        PersistenceController.shared.save()
    }

    /// Call from sensor loop with current step count. Estimates position
    /// using stride length (~0.7m) × heading when GPS is unavailable.
    func updateDeadReckoning(stepCount: Int, heading: Double) {
        let stepDelta = stepCount - lastStepCount
        lastStepCount = stepCount

        guard stepDelta > 0, stepDelta < 20, let _ = currentHeading else { return }
        // Only use dead reckoning when GPS is stale (> 10s) or indoors
        let gpsAge = currentLocation?.timestamp.timeIntervalSinceNow ?? -999
        let useDeadReckoning = (gpsAge < -10 || currentLocation == nil || currentLocation!.horizontalAccuracy > 30)

        if useDeadReckoning {
            // Initialize estimated position from last known GPS or zero
            if estimatedLat == nil, let loc = currentLocation {
                estimatedLat = loc.coordinate.latitude
                estimatedLon = loc.coordinate.longitude
            }
            guard let lat = estimatedLat, let lon = estimatedLon else { return }

            let strideMeters = 0.7 * Double(stepDelta)
            let rad = heading * .pi / 180
            // Heading 0=north → move north (lat +), heading 90=east → move east (lon +)
            estimatedLat = lat + (strideMeters / 111_320) * cos(rad)
            estimatedLon = lon + (strideMeters / (111_320 * cos(lat * .pi / 180))) * sin(rad)

            totalDistance += strideMeters
            // Advance the recorded anchor to the dead-reckoned estimate. Without
            // this, a recovering GPS fix measures from the stale pre-outage
            // coordinate and re-adds the distance already counted here (the
            // outage stretch is counted twice).
            let estLat = estimatedLat!
            let estLon = estimatedLon!
            lastRecordedCoord = CLLocationCoordinate2D(latitude: estLat, longitude: estLon)

            if let session = currentSession {
                let ctx = PersistenceController.shared.container.viewContext
                _ = PathPoint.create(in: ctx, lat: estLat, lon: estLon,
                                     ambientLight: currentAmbientLight,
                                     torchBrightness: currentTorchBrightness,
                                     session: session)
                batchSaveIfDue()
            }
        }
    }

    func startRecording(session: WalkSession) {
        currentSession = session
        totalDistance = 0
        authorizationStatus = manager.authorizationStatus
        isRecording = true
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
    }

    func stopRecording() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        isRecording = false
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        currentHeading = newHeading
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }

    func locationManager(_ manager: CLLocationManager,
                         didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, let session = currentSession else { return }
        currentLocation = location
        // Reset dead reckoning origin when GPS gives a good fix
        if location.horizontalAccuracy < 30 {
            estimatedLat = location.coordinate.latitude
            estimatedLon = location.coordinate.longitude
        }
        // Only record path points (and accrue distance) when the user has
        // actually stepped and the fix is accurate. Distance is measured from
        // the recorded path itself, so it is never double-counted with dead
        // reckoning and never grows while standing still.
        guard externalStepCount > 0 && externalStepCount > lastGPSRecordedStepCount else { return }
        guard location.horizontalAccuracy > 0 && location.horizontalAccuracy < 30 else { return }

        // Heading-based drift filter: if GPS bearing deviates too far from device
        // heading, the point is likely GPS drift — fall back to dead reckoning.
        let isDrift: Bool = {
            guard let prevCoord = lastRecordedCoord,
                  let heading = currentHeading?.trueHeading, heading >= 0 else { return false }
            let bearing = prevCoord.bearing(to: location.coordinate)
            var deviation = abs(bearing - heading)
            if deviation > 180 { deviation = 360 - deviation }
            return deviation > headingFilterThreshold
        }()

        let stepDelta = externalStepCount - lastGPSRecordedStepCount
        lastGPSRecordedStepCount = externalStepCount
        let ctx = PersistenceController.shared.container.viewContext

        if isDrift {
            // Synthesize a point via dead reckoning when GPS is drifting.
            guard let prevCoord = lastRecordedCoord,
                  let heading = currentHeading?.trueHeading, heading >= 0 else { return }
            let strideMeters = 0.7 * Double(max(stepDelta, 1))
            let rad = heading * .pi / 180
            let newLat = prevCoord.latitude + (strideMeters / 111_320) * cos(rad)
            let newLon = prevCoord.longitude + (strideMeters / (111_320 * cos(prevCoord.latitude * .pi / 180))) * sin(rad)
            lastRecordedCoord = CLLocationCoordinate2D(latitude: newLat, longitude: newLon)
            totalDistance += strideMeters
            _ = PathPoint.create(in: ctx, lat: newLat, lon: newLon,
                                 ambientLight: currentAmbientLight,
                                 torchBrightness: currentTorchBrightness,
                                 session: session)
            batchSaveIfDue()
        } else {
            if let prev = lastRecordedCoord {
                let prevLoc = CLLocation(latitude: prev.latitude, longitude: prev.longitude)
                totalDistance += location.distance(from: prevLoc)
            }
            lastRecordedCoord = location.coordinate
            _ = PathPoint.create(in: ctx, lat: location.coordinate.latitude,
                                 lon: location.coordinate.longitude,
                                 ambientLight: currentAmbientLight,
                                 torchBrightness: currentTorchBrightness,
                                 session: session)
            batchSaveIfDue()
        }
    }
}

// MARK: - Coordinate Bearing

extension CLLocationCoordinate2D {
    /// Initial bearing from this coordinate to `other` (degrees, 0=north, clockwise).
    func bearing(to other: CLLocationCoordinate2D) -> Double {
        let dLon = (other.longitude - longitude) * .pi / 180
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
}
