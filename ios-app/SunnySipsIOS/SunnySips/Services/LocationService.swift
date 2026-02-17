import Foundation
import CoreLocation

final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var location: CLLocation?

    private let manager: CLLocationManager
    private var lastLocationRequestAt: Date?

    override init() {
        self.manager = CLLocationManager()
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestPermissionAndLocate() {
        authorizationStatus = manager.authorizationStatus
        switch authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            requestLocationIfAllowed()
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus
            if self.authorizationStatus == .authorizedWhenInUse || self.authorizationStatus == .authorizedAlways {
                self.requestLocationIfAllowed()
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        DispatchQueue.main.async {
            self.location = locations.last
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        _ = error
    }

    private func requestLocationIfAllowed() {
        let now = Date()
        if let last = lastLocationRequestAt, now.timeIntervalSince(last) < 1.0 {
            return
        }
        lastLocationRequestAt = now
        manager.requestLocation()
    }
}
