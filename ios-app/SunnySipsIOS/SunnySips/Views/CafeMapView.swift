import SwiftUI
import MapKit
import Combine

struct CafeMapView: View {
    let cafes: [CafeSnapshot]
    @Binding var selectedCafe: CafeSnapshot?
    let locateRequestID: Int
    var onPermissionDenied: () -> Void = {}

    @State private var position: MapCameraPosition = .automatic
    @StateObject private var locationService = LocationService()
    @State private var pendingCenterOnUser = false
    @State private var didNotifyPermissionDenied = false
    @Namespace private var mapScope

    var body: some View {
        Map(position: $position, selection: $selectedCafe) {
            UserAnnotation()
            ForEach(cafes) { cafe in
                Marker(cafe.name, coordinate: cafe.coordinate)
                    .tint(markerColor(for: cafe))
                    .tag(cafe)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapScope(mapScope)
        .mapControls {
            MapCompass(scope: mapScope)
            MapScaleView(scope: mapScope)
            MapUserLocationButton(scope: mapScope)
        }
        .onAppear {
            fitToCafes(cafes)
            locationService.requestPermissionAndLocate()
        }
        .onChange(of: cafes) { _, newValue in
            fitToCafes(newValue)
        }
        .onChange(of: locateRequestID) { _, _ in
            pendingCenterOnUser = true
            locationService.requestPermissionAndLocate()
            handleAuthorizationChange(locationService.authorizationStatus)
            if let current = locationService.location {
                centerOn(current.coordinate)
                pendingCenterOnUser = false
            }
        }
        .onChange(of: locationService.authorizationStatus) { _, status in
            handleAuthorizationChange(status)
        }
        .onReceive(locationService.$location.compactMap { $0 }) { newLocation in
            guard pendingCenterOnUser else { return }
            centerOn(newLocation.coordinate)
            pendingCenterOnUser = false
        }
    }

    private func markerColor(for cafe: CafeSnapshot) -> Color {
        switch cafe.resolvedBucket {
        case "sunny":
            return ThemeColor.sun
        case "partial":
            return ThemeColor.coffee
        default:
            return ThemeColor.shade
        }
    }

    private func fitToCafes(_ cafes: [CafeSnapshot]) {
        guard !cafes.isEmpty else { return }
        var minLat = cafes[0].lat
        var maxLat = cafes[0].lat
        var minLon = cafes[0].lon
        var maxLon = cafes[0].lon

        for cafe in cafes {
            minLat = min(minLat, cafe.lat)
            maxLat = max(maxLat, cafe.lat)
            minLon = min(minLon, cafe.lon)
            maxLon = max(maxLon, cafe.lon)
        }

        let latPadding = max((maxLat - minLat) * 0.2, 0.005)
        let lonPadding = max((maxLon - minLon) * 0.2, 0.005)
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2.0,
            longitude: (minLon + maxLon) / 2.0
        )

        let region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: (maxLat - minLat) + latPadding,
                longitudeDelta: (maxLon - minLon) + lonPadding
            )
        )
        position = .region(region)
    }

    private func centerOn(_ coordinate: CLLocationCoordinate2D) {
        let region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
        position = .region(region)
    }

    private func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            didNotifyPermissionDenied = false
        case .denied, .restricted:
            if !didNotifyPermissionDenied {
                didNotifyPermissionDenied = true
                pendingCenterOnUser = false
                onPermissionDenied()
            }
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }
}
