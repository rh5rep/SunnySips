import SwiftUI
import MapKit
import UIKit

struct CafeDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let cafe: SunnyCafe
    @Binding var isFavorite: Bool

    @State private var lookAroundScene: MKLookAroundScene?
    @State private var lookAroundLoading = false
    @State private var snapshotImage: UIImage?
    @State private var placesDetails: CafeExternalDetails?
    @State private var placesErrorText: String?
    @State private var isLoadingPlaces = false

    private let placesService = OverpassService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    lookAroundHeader

                    HStack(alignment: .top) {
                        Text(cafe.name)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            isFavorite.toggle()
                        } label: {
                            Image(systemName: isFavorite ? "heart.fill" : "heart")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(isFavorite ? ThemeColor.accentGold : .secondary)
                                .padding(8)
                                .background(Color(.secondarySystemBackground), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isFavorite ? "Remove favorite" : "Add favorite")
                    }

                    HStack(spacing: 10) {
                        metricPill("Score \(Int(cafe.sunnyScore.rounded()))/100", color: markerColor)
                        metricPill("Direct sun \(cafe.sunnyPercentString) (geometry)", color: markerColor)
                    }
                    HStack(spacing: 8) {
                        Text("\(condition.emoji) \(condition.rawValue)")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(condition.color)
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(.secondary)
                            .help("Condition uses sun + cloud forecast.")
                    }
                    .accessibilityLabel("\(condition.rawValue) condition")

                    Text("Score = direct sun x weather factor")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        detailRow("Cloud", value: "\(Int(cafe.cloudCoverPct ?? 0))%")
                        detailRow("Sun elevation", value: String(format: "%.1f°", cafe.sunElevationDeg))
                        detailRow("Sun azimuth", value: String(format: "%.1f°", cafe.sunAzimuthDeg))
                        detailRow("Coordinates", value: String(format: "%.5f, %.5f", cafe.lat, cafe.lon))
                    }
                    .font(.subheadline)

                    placesSection

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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                    .accessibilityLabel("Close details")
                }
            }
            .task(id: cafe.id) {
                await loadLookAround()
                await loadMapSnapshot()
                await loadPlacesDetails()
            }
        }
    }

    private var markerColor: Color {
        condition.color
    }

    private var condition: EffectiveCondition {
        cafe.effectiveCondition(at: Date(), cloudCover: cafe.cloudCoverPct ?? 50.0)
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

    @ViewBuilder
    private var placesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Extra details")
                    .font(.headline)
                Spacer()
                if isLoadingPlaces {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let placesDetails {
                if let address = placesDetails.formattedAddress {
                    detailRow("Address", value: address)
                }
                if let cuisine = placesDetails.cuisine {
                    detailRow("Cuisine", value: cuisine)
                }
                if let outdoor = placesDetails.outdoorSeating {
                    detailRow("Outdoor seating", value: outdoor ? "Yes" : "No")
                }
                if let phone = placesDetails.phone {
                    detailRow("Phone", value: phone)
                }

                if placesDetails.openingHours.isEmpty {
                    Text("Opening hours unavailable")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Hours")
                        .font(.subheadline.weight(.semibold))
                    ForEach(placesDetails.openingHours, id: \.self) { line in
                        Text(line)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(placesDetails.menuText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let website = placesDetails.websiteURL {
                    Link(destination: website) {
                        Label("Open website", systemImage: "safari")
                    }
                    .font(.subheadline.weight(.semibold))
                }
            } else if let placesErrorText {
                Text(placesErrorText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("No extra metadata yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var lookAroundHeader: some View {
        if let lookAroundScene {
            LookAroundPreview(initialScene: lookAroundScene)
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .topLeading) {
                    Text("Area preview")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(10)
                }
        } else if let snapshotImage {
            Image(uiImage: snapshotImage)
                .resizable()
                .scaledToFill()
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .topLeading) {
                    Text("Area preview")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(10)
                }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [markerColor.opacity(0.45), Color(.tertiarySystemBackground)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                VStack(spacing: 8) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(markerColor)
                    Text(lookAroundLoading ? "Loading area preview..." : "No area preview here")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .frame(height: 160)
        }
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

    private func loadLookAround() async {
        lookAroundLoading = true
        defer { lookAroundLoading = false }
        do {
            let request = MKLookAroundSceneRequest(coordinate: cafe.coordinate)
            lookAroundScene = try await request.scene
        } catch {
            lookAroundScene = nil
        }
    }

    private func loadMapSnapshot() async {
        let region = MKCoordinateRegion(
            center: cafe.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.0055, longitudeDelta: 0.0055)
        )
        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = CGSize(width: 900, height: 360)
        options.showsBuildings = true
        options.pointOfInterestFilter = .includingAll

        let snapshotter = MKMapSnapshotter(options: options)
        do {
            let shot = try await snapshotter.start()
            snapshotImage = shot.image
        } catch {
            snapshotImage = nil
        }
    }

    private func loadPlacesDetails() async {
        isLoadingPlaces = true
        defer { isLoadingPlaces = false }

        do {
            let details = try await placesService.fetchDetails(for: cafe)
            placesDetails = details
            placesErrorText = nil
        } catch {
            placesDetails = nil
            placesErrorText = "Limited info from OpenStreetMap. Using snapshot data only."
        }
    }
}
