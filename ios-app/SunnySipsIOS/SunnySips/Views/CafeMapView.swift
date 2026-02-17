import SwiftUI
import MapKit

struct CafeMapView: View {
    let cafes: [CafeSnapshot]
    @Binding var selectedCafe: CafeSnapshot?
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $position, selection: $selectedCafe) {
            ForEach(cafes) { cafe in
                Marker(cafe.name, coordinate: cafe.coordinate)
                    .tint(markerColor(for: cafe))
                    .tag(cafe)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .onAppear {
            fitToCafes(cafes)
        }
        .onChange(of: cafes) { _, newValue in
            fitToCafes(newValue)
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
}
