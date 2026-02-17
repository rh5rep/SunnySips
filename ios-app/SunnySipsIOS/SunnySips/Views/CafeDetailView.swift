import SwiftUI

struct CafeDetailView: View {
    let cafe: CafeSnapshot
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text(cafe.name)
                    .font(.title3.weight(.semibold))

                HStack(spacing: 10) {
                    badge("\(Int(cafe.sunnyScore)) score", color: ThemeColor.sun)
                    badge("\(Int(cafe.sunnyFraction * 100))% sun", color: ThemeColor.coffee)
                    badge(bucketTitle, color: bucketColor)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Sun elevation: \(String(format: "%.1f", cafe.sunElevationDeg))°")
                    Text("Sun azimuth: \(String(format: "%.1f", cafe.sunAzimuthDeg))°")
                    if let cloudCover = cafe.cloudCoverPct {
                        Text("Cloud cover: \(Int(cloudCover))%")
                    }
                    Text("Coordinates: \(String(format: "%.5f", cafe.lat)), \(String(format: "%.5f", cafe.lon))")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Spacer()

                Button {
                    openAppleMaps()
                } label: {
                    Label("Open in Apple Maps", systemImage: "map")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    openStreetView()
                } label: {
                    Label("Open Street View", systemImage: "figure.walk.motion")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(16)
            .navigationTitle("Cafe Details")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func openAppleMaps() {
        let query = cafe.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Cafe"
        let urlString = "http://maps.apple.com/?ll=\(cafe.lat),\(cafe.lon)&q=\(query)"
        if let url = URL(string: urlString) {
            openURL(url)
        }
    }

    private func openStreetView() {
        let urlString = "https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=\(cafe.lat),\(cafe.lon)"
        if let url = URL(string: urlString) {
            openURL(url)
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.2), in: Capsule())
    }

    private var bucketTitle: String {
        switch cafe.resolvedBucket {
        case "sunny": return "Sunny"
        case "partial": return "Partial"
        default: return "Shaded"
        }
    }

    private var bucketColor: Color {
        switch cafe.resolvedBucket {
        case "sunny": return ThemeColor.sun
        case "partial": return ThemeColor.coffee
        default: return ThemeColor.shade
        }
    }
}
