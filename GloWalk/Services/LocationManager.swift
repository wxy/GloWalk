import CoreLocation

@MainActor
final class LocationManager: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published var currentLocation: CLLocation?
    @Published var currentHeading: CLHeading?
    @Published var totalDistance: Double = 0
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isRecording: Bool = false
    @Published var placeName: String?
    @Published var estimatedPathPoints: [PathPoint] = []

    private let manager = CLLocationManager()
    private var currentSession: WalkSession?
    private var lastLocation: CLLocation?
    private var lastRecordedCoord: CLLocationCoordinate2D?  // last valid GPS point saved to path
    private var lastStepCount: Int = 0
    private var lastGPSRecordedStepCount: Int = 0
    private var estimatedLat: Double?
    private var estimatedLon: Double?
    private var hasGeocoded = false
    var externalStepCount: Int = 0  // set from HUDViewModel to gate GPS recording

    /// Maximum allowed deviation (degrees) between GPS bearing and device heading.
    /// Points exceeding this are treated as drift and filtered out.
    private let headingFilterThreshold: Double = 50

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 10
    }

    // MARK: - Pedestrian Dead Reckoning (indoor / no GPS)

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

            // Save estimated point to Core Data
            let ctx = PersistenceController.shared.container.viewContext
            if let session = currentSession {
                let pt = PathPoint.create(in: ctx, lat: estimatedLat!, lon: estimatedLon!,
                                          ambientLight: 0.5, torchBrightness: 0.7, session: session)
                PersistenceController.shared.save()
                estimatedPathPoints.append(pt)
            }
        }
    }

    func startRecording(session: WalkSession) {
        currentSession = session
        lastLocation = nil
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
        if let last = lastLocation {
            totalDistance += location.distance(from: last)
        }
        lastLocation = location

        // Only record path points when user has actually taken steps
        guard externalStepCount > 0 && externalStepCount > lastGPSRecordedStepCount else { return }
        guard location.horizontalAccuracy > 0 && location.horizontalAccuracy < 30 else { return }

        // Heading-based drift filter: if GPS bearing deviates too far from device
        // heading, the point is likely GPS drift — skip it.
        if let prevCoord = lastRecordedCoord,
           let heading = currentHeading?.trueHeading, heading >= 0 {
            let bearing = prevCoord.bearing(to: location.coordinate)
            var deviation = abs(bearing - heading)
            if deviation > 180 { deviation = 360 - deviation }
            if deviation > headingFilterThreshold { return }
        }

        lastGPSRecordedStepCount = externalStepCount
        lastRecordedCoord = location.coordinate
        let ctx = PersistenceController.shared.container.viewContext
        _ = PathPoint.create(in: ctx, lat: location.coordinate.latitude,
                             lon: location.coordinate.longitude,
                             ambientLight: 0.5, torchBrightness: 0.7,
                             session: session)
        PersistenceController.shared.save()

        // Reverse geocode once on first good GPS fix
        if !hasGeocoded && location.horizontalAccuracy < 30 {
            hasGeocoded = true
            CLGeocoder().reverseGeocodeLocation(location) { [weak self] marks, _ in
                guard let place = marks?.first else { return }
                Task { @MainActor in
                    self?.placeName = place.locality ?? place.administrativeArea
                }
            }
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
