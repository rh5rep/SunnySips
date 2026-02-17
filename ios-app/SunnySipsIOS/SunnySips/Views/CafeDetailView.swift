import SwiftUI
import MapKit
import UIKit

struct CafeDetailView: View {
    let cafe: SunnyCafe

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(cafe.name)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)

                    HStack(spacing: 10) {
                        metricPill("Score \(Int(cafe.sunnyScore))", color: markerColor)
                        metricPill("Sunny \(cafe.sunnyPercent)%", color: markerColor)
                        metricPill(cafe.bucket.title, color: markerColor)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        detailRow("Cloud", value: "\(Int(cafe.cloudCoverPct ?? 0))%")
                        detailRow("Sun elevation", value: String(format: "%.1f°", cafe.sunElevationDeg))
                        detailRow("Sun azimuth", value: String(format: "%.1f°", cafe.sunAzimuthDeg))
                        detailRow("Coordinates", value: String(format: "%.5f, %.5f", cafe.lat, cafe.lon))
                    }
                    .font(.subheadline)

                    VStack(spacing: 10) {
                        HStack(spacing: 12) {
                            Button {
                                openAppleMaps()
                            } label: {
                                Label("Open in Maps", systemImage: "map")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                openGoogleMaps()
                            } label: {
                                Label("Google Maps", systemImage: "location.viewfinder")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }

                        Button {
                            openStreetView()
                        } label: {
                            Label("Street View", systemImage: "figure.walk.motion")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Cafe Details")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var markerColor: Color {
        switch cafe.bucket {
        case .sunny: return ThemeColor.sunnyGreen
        case .partial: return ThemeColor.partialAmber
        case .shaded: return ThemeColor.shadedRed
        }
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(.primary)
        }
    }

    private func metricPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.18), in: Capsule())
    }

    private func openAppleMaps() {
        let placemark = MKPlacemark(coordinate: cafe.coordinate)
        let item = MKMapItem(placemark: placemark)
        item.name = cafe.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }

    private func openGoogleMaps() {
        let appURL = URL(string: "comgooglemaps://?daddr=\(cafe.lat),\(cafe.lon)&directionsmode=walking")!
        let webURL = URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(cafe.lat),\(cafe.lon)&travelmode=walking")!
        openPreferApp(appURL, fallback: webURL)
    }

    private func openStreetView() {
        let appURL = URL(string: "comgooglemaps://?center=\(cafe.lat),\(cafe.lon)&mapmode=streetview")!
        let webURL = URL(string: "https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=\(cafe.lat),\(cafe.lon)")!
        openPreferApp(appURL, fallback: webURL)
    }

    private func openPreferApp(_ appURL: URL, fallback webURL: URL) {
        UIApplication.shared.open(appURL, options: [:]) { success in
            if !success {
                UIApplication.shared.open(webURL)
            }
        }
    }
}
