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
    @State private var showNavigateOptions = false
    @State private var showOSMDetails = false
    @State private var showTechnicalDetails = false
    @State private var animateScorePill = false
    @State private var showGeometryHelp = false

    private let placesService = OverpassService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    heroSection

                    if shouldShowSunnyWin {
                        Label("Great sunny pick right now", systemImage: "sparkles")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ThemeColor.sunnyGreen)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(ThemeColor.sunnyGreen.opacity(0.14), in: Capsule())
                            .transition(.opacity.combined(with: .scale))
                    }

                    insightsSection
                    technicalSection
                    osmSection
                    navigationActions
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
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
            .confirmationDialog("Open navigation in", isPresented: $showNavigateOptions, titleVisibility: .visible) {
                Button("Apple Maps") { openAppleMaps() }
                Button("Google Maps") { openGoogleMaps() }
                Button("Street View") { openStreetView() }
                Button("Cancel", role: .cancel) {}
            }
            .popover(isPresented: $showGeometryHelp, attachmentAnchor: .point(.top), arrowEdge: .bottom) {
                Text("Direct sun (geometry) means potential sun exposure if skies were fully clear.")
                    .font(.footnote)
                    .foregroundStyle(ThemeColor.ink)
                    .padding(12)
                    .frame(width: 250, alignment: .leading)
                    .background(ThemeColor.surface)
            }
            .task(id: cafe.id) {
                await loadLookAround()
                await loadMapSnapshot()
                await loadPlacesDetails()
                if shouldShowSunnyWin {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                        animateScorePill = true
                    }
                } else {
                    animateScorePill = true
                }
            }
        }
    }

    private var heroSection: some View {
        ZStack(alignment: .topLeading) {
            heroMedia
                .overlay(
                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.42)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                )

            if shouldShowSunnyWin {
                RadialGradient(
                    colors: [ThemeColor.sunBright.opacity(0.35), .clear],
                    center: .topLeading,
                    startRadius: 10,
                    endRadius: 230
                )
                .allowsHitTesting(false)
            }

            scorePill
                .padding(12)

            VStack {
                Spacer()
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(cafe.name)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.9)

                        Text("\(condition.emoji) \(condition.rawValue)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.95))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            isFavorite.toggle()
                        }
                    } label: {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(isFavorite ? ThemeColor.sunBright : .white)
                            .frame(width: 38, height: 38)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
                }
                .padding(12)
            }
        }
        .frame(height: 250)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Highlights")
                .font(.headline.weight(.bold))
                .foregroundStyle(ThemeColor.ink)

            HStack(spacing: 10) {
                insightCard(
                    title: "Condition",
                    value: condition.rawValue,
                    subtitle: "Score \(scoreOutOf100)",
                    systemImage: condition == .sunny ? "sun.max.fill" : (condition == .partial ? "cloud.sun.fill" : "cloud.fill"),
                    tint: condition.color
                )
                insightCard(
                    title: "Direct Sun",
                    value: cafe.sunnyPercentString,
                    subtitle: "Geometry",
                    systemImage: "sun.horizon.fill",
                    tint: ThemeColor.sun
                ) {
                    Button {
                        showGeometryHelp = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ThemeColor.muted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("What does geometry mean")
                }
            }

            HStack(spacing: 10) {
                insightCard(
                    title: "Sky",
                    value: skySummaryText,
                    subtitle: "Cloud \(Int(cloudCover.rounded()))%",
                    systemImage: skySystemImage,
                    tint: skyTint
                )
                insightCard(
                    title: "Sun",
                    value: String(format: "%.1f°", cafe.sunElevationDeg),
                    subtitle: "Azimuth \(String(format: "%.0f°", cafe.sunAzimuthDeg))",
                    systemImage: "location.north.line.fill",
                    tint: ThemeColor.focusBlue
                )
            }
        }
    }

    private var technicalSection: some View {
        DisclosureGroup(isExpanded: $showTechnicalDetails) {
            VStack(spacing: 10) {
                detailRow("Sun elevation", value: String(format: "%.1f°", cafe.sunElevationDeg))
                detailRow("Sun azimuth", value: String(format: "%.1f°", cafe.sunAzimuthDeg))
                detailRow("Coordinates", value: coordinateText)

                Button {
                    UIPasteboard.general.string = coordinateText
                } label: {
                    Label("Copy coordinates", systemImage: "doc.on.doc")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(ThemeColor.focusBlue)
            }
            .padding(.top, 8)
        } label: {
            Label("Technical details", systemImage: "wrench.and.screwdriver")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ThemeColor.ink)
        }
        .padding(14)
        .background(ThemeColor.surfaceSoft.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var osmSection: some View {
        DisclosureGroup(isExpanded: $showOSMDetails) {
            VStack(alignment: .leading, spacing: 10) {
                if isLoadingPlaces {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading OpenStreetMap details...")
                            .font(.footnote)
                            .foregroundStyle(ThemeColor.muted)
                    }
                } else if let details = placesDetails {
                    if let address = details.formattedAddress {
                        detailRow("Address", value: address)
                    }
                    if let cuisine = details.cuisine {
                        detailRow("Cuisine", value: cuisine)
                    }
                    if let seating = details.outdoorSeating {
                        detailRow("Outdoor seating", value: seating ? "Yes" : "No")
                    }
                    if let phone = details.phone {
                        detailRow("Phone", value: phone)
                    }
                    if let website = details.websiteURL {
                        Link(destination: website) {
                            Label("Website", systemImage: "safari")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    if !details.openingHours.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Hours")
                                .font(.subheadline.weight(.semibold))
                            ForEach(details.openingHours, id: \.self) { line in
                                Text(line)
                                    .font(.footnote)
                                    .foregroundStyle(ThemeColor.muted)
                            }
                        }
                    }
                    Text("Limited info from OpenStreetMap.")
                        .font(.footnote)
                        .foregroundStyle(ThemeColor.muted)
                } else {
                    Text(placesErrorText ?? "Limited info from OpenStreetMap. Using snapshot data only.")
                        .font(.footnote)
                        .foregroundStyle(ThemeColor.muted)
                }
            }
            .padding(.top, 8)
        } label: {
            Label("More from OpenStreetMap", systemImage: "map")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ThemeColor.ink)
        }
        .padding(14)
        .background(ThemeColor.surfaceSoft.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var navigationActions: some View {
        HStack(spacing: 10) {
            Button {
                showNavigateOptions = true
            } label: {
                Label("Navigate", systemImage: "location.fill")
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(ThemeColor.focusBlue, in: Capsule())
            .accessibilityLabel("Navigate to cafe")

            ShareLink(item: shareURL, preview: SharePreview(cafe.name)) {
                Image(systemName: "square.and.arrow.up")
                    .font(.headline.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(ThemeColor.surfaceSoft, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Share cafe")
        }
    }

    @ViewBuilder
    private var heroMedia: some View {
        if let lookAroundScene {
            LookAroundPreview(initialScene: lookAroundScene)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let snapshotImage {
            Image(uiImage: snapshotImage)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ZStack {
                LinearGradient(
                    colors: [ThemeColor.sun.opacity(0.45), ThemeColor.surfaceSoft.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                VStack(spacing: 8) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(ThemeColor.coffeeDark)
                    Text(lookAroundLoading ? "Loading area preview..." : "Area preview unavailable")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(ThemeColor.ink.opacity(0.85))
                }
            }
        }
    }

    private var scorePill: some View {
        Text("\(scoreOutOf100)/100")
            .font(.title3.weight(.bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.9)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(ThemeColor.sun, in: Capsule())
            .scaleEffect(animateScorePill ? 1.0 : 0.92)
            .accessibilityLabel("Score \(scoreOutOf100) out of 100")
    }

    private func insightCard(
        title: String,
        value: String,
        subtitle: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        insightCard(
            title: title,
            value: value,
            subtitle: subtitle,
            systemImage: systemImage,
            tint: tint
        ) {
            EmptyView()
        }
    }

    private func insightCard<T: View>(
        title: String,
        value: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        @ViewBuilder trailingAccessory: () -> T
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ThemeColor.muted)
                    .lineLimit(1)
                Spacer(minLength: 0)
                trailingAccessory()
            }
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(ThemeColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(ThemeColor.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(ThemeColor.surfaceSoft.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(ThemeColor.muted)
            Spacer(minLength: 12)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ThemeColor.ink)
                .multilineTextAlignment(.trailing)
        }
    }

    private var condition: EffectiveCondition {
        cafe.effectiveCondition(at: Date(), cloudCover: cloudCover)
    }

    private var cloudCover: Double {
        cafe.cloudCoverPct ?? 50.0
    }

    private var shouldShowSunnyWin: Bool {
        condition == .sunny && cloudCover < 20.0
    }

    private var scoreOutOf100: Int {
        Int(cafe.sunnyScore.rounded())
    }

    private var coordinateText: String {
        String(format: "%.5f, %.5f", cafe.lat, cafe.lon)
    }

    private var skySummaryText: String {
        let sunnyPct = max(0, min(100, Int((100 - cloudCover).rounded())))
        if sunnyPct >= Int(cloudCover.rounded()) {
            return "Sunny \(sunnyPct)%"
        }
        return "Cloud \(Int(cloudCover.rounded()))%"
    }

    private var skySystemImage: String {
        skySummaryText.contains("Sunny") ? "sun.max.fill" : "cloud.fill"
    }

    private var skyTint: Color {
        skySummaryText.contains("Sunny") ? ThemeColor.sun : ThemeColor.muted
    }

    private var shareURL: URL {
        URL(string: "https://www.google.com/maps/search/?api=1&query=\(cafe.lat),\(cafe.lon)")!
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
        options.size = CGSize(width: 900, height: 500)
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
            placesDetails = try await placesService.fetchDetails(for: cafe)
            placesErrorText = nil
        } catch {
            placesDetails = nil
            placesErrorText = "Limited info from OpenStreetMap. Using snapshot data only."
        }
    }
}
