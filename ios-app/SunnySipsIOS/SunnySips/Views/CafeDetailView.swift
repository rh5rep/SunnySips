import SwiftUI
import MapKit
import UIKit

struct CafeDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("homeCityId") private var homeCityId = AppConfig.homeCityDefault

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
    @State private var showLookAroundViewer = false
    @State private var sunOutlook: CafeSunOutlookResponse?
    @State private var isLoadingSunOutlook = false
    @State private var sunOutlookError: String?

    private let placesService = OverpassService()
    private let recommendationService = RecommendationService()
    private let sunOutlookDays = 5

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        heroSection
                        heroActionRow

                        insightsSection
                        sunOutlookSection
                        technicalSection
                        osmSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                    await loadSunOutlook()
                    if shouldShowSunnyWin {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                            animateScorePill = true
                        }
                    } else {
                        animateScorePill = true
                    }
                }

                if showNavigateOptions {
                    Color.black.opacity(0.42)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                showNavigateOptions = false
                            }
                        }
                }

                if showNavigateOptions {
                    themedNavigationSheet
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(10)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showNavigateOptions)
            .onAppear {
                TelemetryService.track(
                    "sun_outlook_opened",
                    properties: ["cafe_id": cafe.id, "city_id": homeCityId]
                )
            }
            .sheet(isPresented: $showLookAroundViewer) {
                lookAroundViewerSheet
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(ThemeColor.surface)
            }
        }
    }

    private var heroSection: some View {
        ZStack(alignment: .topTrailing) {
            heroMedia
                .contentShape(Rectangle())
                .onTapGesture {
                    if lookAroundScene != nil {
                        showLookAroundViewer = true
                    }
                }
                .overlay(
                    LinearGradient(
                        colors: [Color.black.opacity(0.12), Color.black.opacity(0.58)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)
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
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.44), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Spacer(minLength: 8)

                    HStack(spacing: 8) {
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

                        ShareLink(item: shareURL, preview: SharePreview(cafe.name)) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Share cafe")
                    }
                }
                .padding(12)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 250)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var heroActionRow: some View {
        HStack(spacing: 10) {
            Label(
                pickTypeText,
                systemImage: pickTypeSymbol
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(condition.color, in: Capsule())

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showNavigateOptions = true
                }
            } label: {
                Label("Navigate", systemImage: "location.fill")
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(ThemeColor.focusBlue, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Navigate to cafe")
        }
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
                    title: "Sun time left",
                    value: expectedSunTimeLeftText,
                    subtitle: expectedSunTimeLeftSubtitle,
                    systemImage: "timer",
                    tint: condition.color
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

    private var sunOutlookSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Sun Outlook (\(sunOutlookDays) days)")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(ThemeColor.ink)
                Spacer(minLength: 8)
                if let status = sunOutlook?.dataStatus, status == .stale, let hours = sunOutlook?.freshnessHours {
                    Text("Using \(Int(hours.rounded()))h old data")
                        .font(.caption2)
                        .foregroundStyle(ThemeColor.muted)
                }
            }
            if let outlook = sunOutlook {
                Text("Source: \(outlook.providerUsed ?? "unknown") • \(outlook.dataStatus.rawValue)")
                    .font(.caption2)
                    .foregroundStyle(ThemeColor.muted)
            }
            if outlookCoverageDayCount > 0, outlookCoverageDayCount < sunOutlookDays {
                Text("Showing \(outlookCoverageDayCount) of \(sunOutlookDays) days (limited forecast data).")
                    .font(.caption2)
                    .foregroundStyle(ThemeColor.muted)
            }

            if isLoadingSunOutlook {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading sun windows...")
                        .font(.footnote)
                        .foregroundStyle(ThemeColor.muted)
                }
            } else {
                if let summaries = dailyOutlookSummaries, !summaries.isEmpty {
                    dailyOutlookCarousel(summaries)
                }

                if let grouped = groupedSunOutlookWindows, !grouped.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(grouped, id: \.day) { group in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(group.day)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ThemeColor.ink)
                                ForEach(group.windows, id: \.id) { window in
                                    Text("\(window.startLocal.formattedDayTime())-\(window.endLocal.formattedTimeOnly()) • \(window.condition.capitalized) • \(window.durationMin)m")
                                        .font(.footnote)
                                        .foregroundStyle(ThemeColor.muted)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(ThemeColor.surfaceSoft.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .onAppear {
                                TelemetryService.track(
                                    "sun_outlook_day_expanded",
                                    properties: ["cafe_id": cafe.id, "day": group.day]
                                )
                            }
                        }
                    }
                } else if let error = sunOutlookError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(ThemeColor.muted)
                } else {
                    Text(noSunnyWindowsMessage)
                        .font(.footnote)
                        .foregroundStyle(ThemeColor.muted)
                }
            }
        }
    }

    private func dailyOutlookCarousel(_ summaries: [DailyOutlookSummary]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(summaries) { day in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(day.dayLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ThemeColor.ink)
                        Text("Cloud \(day.averageCloudPct)%")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(ThemeColor.muted)
                        Text(day.sunSlots > 0 ? "\(day.sunSlots) sunny slots" : "No sunny slots")
                            .font(.caption2)
                            .foregroundStyle(day.sunSlots > 0 ? ThemeColor.focusBlue : ThemeColor.muted)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(ThemeColor.surfaceSoft.opacity(0.74), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(.bottom, 2)
        }
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

    private var themedNavigationSheet: some View {
        VStack {
            Spacer()
            VStack(spacing: 10) {
                Capsule()
                    .fill(ThemeColor.line.opacity(0.9))
                    .frame(width: 36, height: 5)
                    .padding(.top, 8)

                Text("Navigate With")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(ThemeColor.ink)

                VStack(spacing: 8) {
                    navigationOptionButton("Apple Maps", systemImage: "map.fill", action: openAppleMaps)
                    navigationOptionButton("Google Maps", systemImage: "globe", action: openGoogleMaps)
                    navigationOptionButton("Street View", systemImage: "figure.walk", action: openStreetView)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showNavigateOptions = false
                    }
                } label: {
                    Text("Cancel")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ThemeColor.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(ThemeColor.surfaceSoft, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(
                ThemeColor.surface.opacity(0.98),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(ThemeColor.line.opacity(0.7), lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func navigationOptionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                showNavigateOptions = false
            }
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ThemeColor.muted)
            }
            .foregroundStyle(ThemeColor.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(ThemeColor.surfaceSoft.opacity(0.88), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var heroMedia: some View {
        if let lookAroundScene {
            LookAroundPreview(initialScene: lookAroundScene)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else if let snapshotImage {
            GeometryReader { proxy in
                Image(uiImage: snapshotImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            }
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
    }

    private var lookAroundViewerSheet: some View {
        NavigationStack {
            ZStack {
                ThemeColor.bg.ignoresSafeArea()
                if let lookAroundScene {
                    LookAroundPreview(initialScene: lookAroundScene)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "binoculars.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(ThemeColor.muted)
                        Text("Look Around unavailable for this location")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ThemeColor.ink)
                    }
                    .padding(20)
                }
            }
            .navigationTitle(cafe.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showLookAroundViewer = false
                    }
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
            .background(condition.color, in: Capsule())
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

    private var pickTypeText: String {
        switch condition {
        case .sunny: return "Great Pick"
        case .partial: return "Some Sun"
        case .shaded: return "No Sun"
        }
    }

    private var pickTypeSymbol: String {
        switch condition {
        case .sunny: return "sparkles"
        case .partial: return "cloud.sun.fill"
        case .shaded: return "cloud.fill"
        }
    }

    private var scoreOutOf100: Int {
        Int(cafe.sunnyScore.rounded())
    }

    private var estimatedSunMinutes: Int {
        guard cafe.sunElevationDeg > 0 else { return 0 }

        let baseMinutes: Double
        switch condition {
        case .sunny:
            baseMinutes = 95
        case .partial:
            baseMinutes = 48
        case .shaded:
            baseMinutes = 10
        }

        let elevationFactor = max(0.25, min(1.0, cafe.sunElevationDeg / 24.0))
        let cloudFactor = max(0.2, 1.0 - (cloudCover / 100.0) * 0.75)
        var estimate = baseMinutes * elevationFactor * cloudFactor

        if cafe.sunElevationDeg < 6 {
            estimate = min(estimate, 20)
        }
        if condition == .shaded {
            estimate = min(estimate, 10)
        }

        let roundedToFive = Int((estimate / 5.0).rounded()) * 5
        return max(0, roundedToFive)
    }

    private var expectedSunTimeLeftText: String {
        if condition == .shaded {
            return shadedForecastSunText
        }
        if estimatedSunMinutes <= 0 { return "0-5 min" }
        if estimatedSunMinutes >= 90 { return "90+ min" }
        return "\(estimatedSunMinutes) min"
    }

    private var expectedSunTimeLeftSubtitle: String {
        if condition == .shaded {
            return shadedForecastSunSubtitle
        }
        if cafe.sunElevationDeg < 6 { return "Sun dropping soon" }
        return "Current estimate"
    }

    private var shadedForecastSunText: String {
        let forecast = shadedForecastForToday
        if forecast.expectedToday {
            if let nextTime = forecast.nextSunTime {
                return "After \(forecastTimeText(nextTime))"
            }
            return "Before sunset"
        }
        return "No sun today"
    }

    private var shadedForecastSunSubtitle: String {
        shadedForecastForToday.expectedToday ? "Sun expected today" : "No sun expected today"
    }

    private var shadedForecastForToday: (expectedToday: Bool, nextSunTime: Date?) {
        let now = Date()
        let timeZone = TimeZone(identifier: "Europe/Copenhagen") ?? .current
        guard let window = SunlightCalculator.daylightWindow(
            on: now,
            coordinate: cafe.coordinate,
            timeZone: timeZone
        ) else {
            return (false, nil)
        }

        if now >= window.sunset {
            return (false, nil)
        }

        if now < window.sunrise {
            return (true, window.sunrise)
        }

        let minutesToSunset = Int(window.sunset.timeIntervalSince(now) / 60.0)
        if cloudCover >= EffectiveCondition.heavyCloudOverrideThreshold || minutesToSunset < 20 {
            return (false, nil)
        }

        // Use a lightweight cloud-based heuristic to provide an estimated "next sun" time today.
        let estimateMinutes: Int?
        switch cloudCover {
        case ..<35:
            estimateMinutes = 15
        case ..<55:
            estimateMinutes = 30
        case ..<70:
            estimateMinutes = 60
        case ..<EffectiveCondition.heavyCloudOverrideThreshold where minutesToSunset >= 120:
            estimateMinutes = 90
        default:
            estimateMinutes = nil
        }

        if let estimateMinutes {
            let estimated = now.addingTimeInterval(Double(estimateMinutes) * 60.0)
            let safeSunset = window.sunset.addingTimeInterval(-10 * 60.0)
            return (true, min(estimated, safeSunset))
        }

        return (false, nil)
    }

    private func forecastTimeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Date.copenhagenCalendar
        formatter.timeZone = TimeZone(identifier: "Europe/Copenhagen") ?? .current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
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

    private func loadSunOutlook() async {
        isLoadingSunOutlook = true
        sunOutlookError = nil
        defer { isLoadingSunOutlook = false }

        do {
            let response = try await recommendationService.fetchCafeSunWindows(
                cafeId: cafe.id,
                cityId: "copenhagen",
                days: sunOutlookDays,
                minDuration: 30
            )
            sunOutlook = response
            let coverageDays = Set(response.hourly.map { String($0.timeLocal.prefix(10)) }).count
            print("[CafeDetail] SunOutlook loaded cafe=\(cafe.id) provider=\(response.providerUsed ?? "none") status=\(response.dataStatus.rawValue) fallback=\(response.fallbackUsed) hourly=\(response.hourly.count) windows=\(response.windows.count) coverageDays=\(coverageDays)")
            if response.dataStatus == .unavailable {
                sunOutlookError = "Temporarily unavailable—check connection."
            }
        } catch {
            print("[CafeDetail] SunOutlook error cafe=\(cafe.id) city=copenhagen error=\(error)")
            sunOutlook = nil
            sunOutlookError = "Temporarily unavailable—check connection."
        }
    }

    private struct DailyOutlookSummary: Identifiable {
        let id: String
        let dayLabel: String
        let averageCloudPct: Int
        let sunSlots: Int
    }

    private var dailyOutlookSummaries: [DailyOutlookSummary]? {
        guard let hourly = sunOutlook?.hourly, !hourly.isEmpty else { return nil }
        var grouped: [String: [SunOutlookHourlyPoint]] = [:]
        for point in hourly {
            let key = String(point.timeLocal.prefix(10))
            grouped[key, default: []].append(point)
        }

        return grouped
            .map { key, rows in
                let clouds = rows.compactMap(\.cloudCoverPct)
                let avgCloud = clouds.isEmpty
                    ? 50
                    : Int((clouds.reduce(0, +) / Double(clouds.count)).rounded())
                let sunSlots = rows.filter { isSunWindowCondition($0.condition) }.count
                return DailyOutlookSummary(
                    id: key,
                    dayLabel: rows.first?.timeLocal.formattedDayOnly() ?? key,
                    averageCloudPct: max(0, min(100, avgCloud)),
                    sunSlots: sunSlots
                )
            }
            .sorted { $0.id < $1.id }
    }

    private var noSunnyWindowsMessage: String {
        guard let summaries = dailyOutlookSummaries, !summaries.isEmpty else {
            return "No sunny/partial windows in next \(sunOutlookDays) days"
        }
        let allNoSun = summaries.allSatisfy { $0.sunSlots == 0 }
        if allNoSun {
            return "No sunny/partial windows in next \(sunOutlookDays) days. Forecast stays mostly cloudy/shaded."
        }
        return "No windows meet the minimum duration in next \(sunOutlookDays) days."
    }

    private func isSunWindowCondition(_ condition: String) -> Bool {
        let normalized = condition.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "sunny" || normalized == "partial"
    }

    private var outlookCoverageDayCount: Int {
        dailyOutlookSummaries?.count ?? 0
    }

    private var groupedSunOutlookWindows: [(day: String, windows: [SunOutlookWindow])]? {
        guard let windows = sunOutlook?.windows, !windows.isEmpty else { return nil }
        var buckets: [String: [SunOutlookWindow]] = [:]
        for window in windows {
            let key = String(window.startLocal.prefix(10))
            buckets[key, default: []].append(window)
        }
        return buckets
            .map { key, values in
                (
                    day: values.first?.startLocal.formattedDayOnly() ?? key,
                    windows: values.sorted { $0.startLocal < $1.startLocal },
                    key: key
                )
            }
            .sorted { $0.key < $1.key }
            .map { (day: $0.day, windows: $0.windows) }
    }
}

private extension String {
    func formattedDayOnly() -> String {
        guard let date = ISO8601DateFormatter.withFractionalSeconds.date(from: self)
            ?? ISO8601DateFormatter.internetDateTime.date(from: self)
        else {
            return self
        }
        let formatter = DateFormatter()
        formatter.calendar = Date.copenhagenCalendar
        formatter.timeZone = TimeZone(identifier: "Europe/Copenhagen")
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: date)
    }

    func formattedDayTime() -> String {
        guard let date = ISO8601DateFormatter.withFractionalSeconds.date(from: self)
            ?? ISO8601DateFormatter.internetDateTime.date(from: self)
        else {
            return self
        }
        let formatter = DateFormatter()
        formatter.calendar = Date.copenhagenCalendar
        formatter.timeZone = TimeZone(identifier: "Europe/Copenhagen")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    func formattedTimeOnly() -> String {
        formattedDayTime()
    }
}
