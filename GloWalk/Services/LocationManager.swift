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
    private var lastLocation: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 10
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
        if let last = lastLocation {
            totalDistance += location.distance(from: last)
        }
        lastLocation = location

        let ctx = PersistenceController.shared.container.viewContext
        _ = PathPoint.create(in: ctx, lat: location.coordinate.latitude,
                             lon: location.coordinate.longitude,
                             ambientLight: 0.5, torchBrightness: 0.7,
                             session: session)
        PersistenceController.shared.save()
    }
}
