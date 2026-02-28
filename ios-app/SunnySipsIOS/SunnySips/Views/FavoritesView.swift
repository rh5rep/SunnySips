import SwiftUI

private enum FavoritesSegment: String, CaseIterable, Identifiable {
    case recommendations = "Recommendations"
    case saved = "Saved"

    var id: String { rawValue }
}

struct FavoritesView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("homeCityId") private var homeCityId = AppConfig.homeCityDefault

    let cafes: [SunnyCafe]
    let recommendations: [FavoriteRecommendationItem]
    let recommendationStatus: RecommendationDataStatus
    let recommendationFreshnessHours: Double?
    let recommendationProviderUsed: String?
    let recommendationError: String?
    let visibleFavoriteCount: Int
    let totalFavoriteCount: Int
    let isFavoritesCapped: Bool
    let onRefreshRecommendations: () async -> Void
    let onTapCafe: (SunnyCafe) -> Void
    let onRemoveFavorite: (SunnyCafe) -> Void
    @State private var showAllRecommendations = false
    @State private var expandedRecommendationDayIDs: Set<String> = []
    @State private var selectedSegment: FavoritesSegment = .recommendations
    @State private var hasSetInitialSegment = false

    var body: some View {
        NavigationStack {
            Group {
                if totalFavoriteCount == 0 {
                    ContentUnavailableView(
                        "No Favorites Yet",
                        systemImage: "heart",
                        description: Text("Tap the heart in a cafe detail card to save favorites.")
                    )
                } else {
                    List {
                        controlsSection
                        if selectedSegment == .recommendations {
                            recommendationsSection
                        } else {
                            savedFavoritesSection
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Favorites")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                    .accessibilityLabel("Close favorites")
                }
            }
            .task {
                await onRefreshRecommendations()
                setInitialSegmentIfNeeded()
                TelemetryService.track(
                    "recommendation_impression",
                    properties: [
                        "status": recommendationStatus.rawValue,
                        "count": "\(recommendations.count)",
                        "segment": selectedSegment.rawValue.lowercased(),
                        "is_capped": isFavoritesCapped ? "true" : "false",
                        "visible_favorites_count": "\(visibleFavoriteCount)"
                    ]
                )
            }
            .onChange(of: selectedSegment) { _, newValue in
                if newValue != .recommendations {
                    showAllRecommendations = false
                    expandedRecommendationDayIDs.removeAll()
                }
                TelemetryService.track(
                    "favorites_segment_changed",
                    properties: [
                        "segment": newValue.rawValue.lowercased(),
                        "is_capped": isFavoritesCapped ? "true" : "false",
                        "visible_favorites_count": "\(visibleFavoriteCount)"
                    ]
                )
            }
            .onChange(of: recommendations.count) { _, _ in
                setInitialSegmentIfNeeded()
                if showAllRecommendations {
                    primeExpandedRecommendationDays()
                }
            }
            .onChange(of: showAllRecommendations) { _, isExpanded in
                if isExpanded {
                    primeExpandedRecommendationDays()
                } else {
                    expandedRecommendationDayIDs.removeAll()
                }
            }
        }
    }

    private func setInitialSegmentIfNeeded() {
        guard !hasSetInitialSegment else { return }
        selectedSegment = recommendations.isEmpty ? .saved : .recommendations
        hasSetInitialSegment = true
    }

    @ViewBuilder
    private var controlsSection: some View {
        Section {
            Picker("Favorites segment", selection: $selectedSegment) {
                ForEach(FavoritesSegment.allCases) { segment in
                    Text(segment.rawValue).tag(segment)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Favorites view mode")

            if isFavoritesCapped {
                Text("Showing top \(visibleFavoriteCount) of \(totalFavoriteCount) favorites, prioritized by best upcoming sun.")
                    .font(.caption2)
                    .foregroundStyle(ThemeColor.muted)
            }
        }
    }

    @ViewBuilder
    private var savedFavoritesSection: some View {
        Section("Saved Favorites") {
            if cafes.isEmpty {
                Text("No visible favorites in the current top \(visibleFavoriteCount).")
                    .font(.subheadline)
                    .foregroundStyle(ThemeColor.muted)
            } else {
                ForEach(cafes) { cafe in
                    Button {
                        onTapCafe(cafe)
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(cafe.effectiveCondition.color)
                                .frame(width: 10, height: 10)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(cafe.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text("\(cafe.effectiveCondition.emoji) \(cafe.effectiveCondition.rawValue) • Score \(cafe.scoreString)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "heart.fill")
                                .foregroundStyle(ThemeColor.accentGold)
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            onRemoveFavorite(cafe)
                        } label: {
                            Label("Remove", systemImage: "heart.slash")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var recommendationsSection: some View {
        Section("Recommended Visit Times") {
            Text("Source: \(recommendationProviderUsed ?? "unknown") • \(recommendationStatus.rawValue)")
                .font(.caption2)
                .foregroundStyle(ThemeColor.muted)
            if recommendationStatus == .stale, let freshness = recommendationFreshnessHours {
                Text("Using \(Int(freshness.rounded()))h old data")
                    .font(.caption2)
                    .foregroundStyle(ThemeColor.muted)
            }

            if recommendations.isEmpty {
                Text("No strong sun windows right now. We'll keep watching your favorites.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .onAppear {
                        TelemetryService.track(
                            "recommendation_empty_state_seen",
                            properties: [
                                "segment": selectedSegment.rawValue.lowercased(),
                                "is_capped": isFavoritesCapped ? "true" : "false",
                                "visible_favorites_count": "\(visibleFavoriteCount)"
                            ]
                        )
                    }
                if let recommendationError, !recommendationError.isEmpty {
                    Text(recommendationError)
                        .font(.caption2)
                        .foregroundStyle(ThemeColor.muted)
                }
            } else {
                if showAllRecommendations {
                    ForEach(groupedExpandedRecommendations) { group in
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedRecommendationDayIDs.contains(group.id) },
                                set: { expanded in
                                    if expanded {
                                        expandedRecommendationDayIDs.insert(group.id)
                                    } else {
                                        expandedRecommendationDayIDs.remove(group.id)
                                    }
                                }
                            )
                        ) {
                            VStack(spacing: 8) {
                                ForEach(group.items) { item in
                                    recommendationCard(item)
                                }
                            }
                            .padding(.top, 6)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(ThemeColor.ink)
                                Text(group.summary)
                                    .font(.caption2)
                                    .foregroundStyle(ThemeColor.muted)
                            }
                        }
                        .accessibilityLabel("\(group.title), \(group.summary)")
                    }
                } else {
                    ForEach(collapsedRecommendations) { item in
                        recommendationCard(item)
                    }
                }

                if recommendations.count > collapsedRecommendations.count {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showAllRecommendations.toggle()
                        }
                    } label: {
                        Text(showAllRecommendations ? "Show less" : "Show more")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ThemeColor.focusBlue)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func recommendationCard(_ item: FavoriteRecommendationItem) -> some View {
        Button {
            if let cafe = cafes.first(where: { $0.id == item.cafeID }) {
                TelemetryService.track(
                    "recommendation_tapped",
                    properties: [
                        "city_id": homeCityId,
                        "cafe_id": item.cafeID,
                        "segment": selectedSegment.rawValue.lowercased(),
                        "is_capped": isFavoritesCapped ? "true" : "false",
                        "visible_favorites_count": "\(visibleFavoriteCount)"
                    ]
                )
                onTapCafe(cafe)
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                CafeLogoBadgeView(
                    cafeName: item.cafeName,
                    fallbackTint: recommendationTint(for: item.condition)
                )
                .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(item.cafeName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ThemeColor.ink)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(item.startLocal.formattedRecommendationDay())
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(ThemeColor.focusBlue)
                            .lineLimit(1)
                    }
                    Text("\(item.startLocal.formattedTimeOnly())-\(item.endLocal.formattedTimeOnly()) • \(item.durationMin)m")
                        .font(.caption)
                        .foregroundStyle(ThemeColor.muted)
                        .lineLimit(1)
                    Text(item.reason)
                        .font(.caption2)
                        .foregroundStyle(ThemeColor.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                ThemeColor.surfaceSoft.opacity(0.74),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.cafeName), \(item.startLocal.formattedRecommendationDay()), \(item.condition), \(item.startLocal.formattedTimeOnly()) to \(item.endLocal.formattedTimeOnly())")
    }

    private var collapsedRecommendations: [FavoriteRecommendationItem] {
        var byCafe: [String: FavoriteRecommendationItem] = [:]
        for item in recommendations.sorted(by: recommendationSort) {
            if byCafe[item.cafeID] == nil {
                byCafe[item.cafeID] = item
            }
        }
        return Array(byCafe.values)
            .sorted(by: recommendationSort)
            .prefix(3)
            .map { $0 }
    }

    private var expandedRecommendations: [FavoriteRecommendationItem] {
        recommendations
            .sorted(by: recommendationSort)
            .prefix(10)
            .map { $0 }
    }

    private struct RecommendationGroup: Identifiable {
        let id: String
        let title: String
        let summary: String
        let sortDate: Date
        let isToday: Bool
        let bestScore: Double
        let items: [FavoriteRecommendationItem]
    }

    private var groupedExpandedRecommendations: [RecommendationGroup] {
        let grouped = Dictionary(grouping: expandedRecommendations) { item in
            item.startLocal.recommendationDayKey()
        }

        return grouped.compactMap { dayKey, items in
            let sortedItems = items.sorted(by: recommendationSort)
            guard let firstDate = sortedItems
                .compactMap({ ISODateParser.parse($0.startUTC) })
                .min()
            else {
                return nil
            }
            let best = sortedItems.first
            let summary = best.map {
                "\(sortedItems.count) windows • Best \($0.startLocal.formattedTimeOnly())-\($0.endLocal.formattedTimeOnly()) • \($0.durationMin)m"
            } ?? "\(sortedItems.count) windows"
            return RecommendationGroup(
                id: dayKey,
                title: dayKey.formattedRecommendationDayKeyTitle(),
                summary: summary,
                sortDate: firstDate,
                isToday: Date.copenhagenCalendar.isDateInToday(firstDate),
                bestScore: sortedItems.map(\.score).max() ?? 0.0,
                items: sortedItems
            )
        }
        .sorted { $0.sortDate < $1.sortDate }
    }

    private func primeExpandedRecommendationDays() {
        let groups = groupedExpandedRecommendations
        guard !groups.isEmpty else { return }
        var expanded: Set<String> = []
        if let todayGroup = groups.first(where: { $0.isToday }) {
            expanded.insert(todayGroup.id)
        }
        if let bestGroup = groups.max(by: { $0.bestScore < $1.bestScore }) {
            expanded.insert(bestGroup.id)
        }
        if expanded.isEmpty, let first = groups.first {
            expanded.insert(first.id)
        }
        expandedRecommendationDayIDs = expanded
    }

    private func recommendationSort(_ lhs: FavoriteRecommendationItem, _ rhs: FavoriteRecommendationItem) -> Bool {
        let leftDate = ISODateParser.parse(lhs.startUTC) ?? .distantFuture
        let rightDate = ISODateParser.parse(rhs.startUTC) ?? .distantFuture
        if leftDate != rightDate {
            return leftDate < rightDate
        }
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }
        return lhs.cafeName.localizedCaseInsensitiveCompare(rhs.cafeName) == .orderedAscending
    }

    private func recommendationTint(for condition: String) -> Color {
        switch condition.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "sunny":
            return ThemeColor.sun
        case "partial":
            return ThemeColor.partialAmber
        default:
            return ThemeColor.muted
        }
    }
}

private struct CafeLogoBadgeView: View {
    let cafeName: String
    let fallbackTint: Color

    var body: some View {
        Group {
            if let logoURL = CafeLogoResolver.logoURL(forCafeName: cafeName) {
                AsyncImage(url: logoURL, transaction: Transaction(animation: .easeInOut(duration: 0.12))) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallbackView
                    }
                }
            } else {
                fallbackView
            }
        }
        .frame(width: 18, height: 18)
        .clipShape(Circle())
    }

    private var fallbackView: some View {
        ZStack {
            Circle()
                .fill(ThemeColor.surfaceSoft.opacity(0.95))
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(fallbackTint)
        }
    }
}

private extension String {
    func recommendationDayKey() -> String {
        guard let date = ISODateParser.parse(self) else {
            return self
        }
        let formatter = DateFormatter()
        formatter.calendar = Date.copenhagenCalendar
        formatter.timeZone = TimeZone(identifier: "Europe/Copenhagen")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    func formattedRecommendationDayKeyTitle() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Date.copenhagenCalendar
        formatter.timeZone = TimeZone(identifier: "Europe/Copenhagen")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: self) else {
            return self
        }
        return date.formattedRecommendationDayTitle()
    }

    func formattedRecommendationDay() -> String {
        guard let date = ISODateParser.parse(self) else {
            return self
        }
        return date.formattedRecommendationDayTitle()
    }

    func formattedTimeOnly() -> String {
        guard let date = ISODateParser.parse(self)
        else {
            return self
        }
        let formatter = DateFormatter()
        formatter.calendar = Date.copenhagenCalendar
        formatter.timeZone = TimeZone(identifier: "Europe/Copenhagen")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

private extension Date {
    func formattedRecommendationDayTitle() -> String {
        let calendar = Date.copenhagenCalendar
        let now = Date()
        if calendar.isDate(self, inSameDayAs: now) {
            return "Today"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(self, inSameDayAs: tomorrow) {
            return "Tomorrow"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = TimeZone(identifier: "Europe/Copenhagen")
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: self)
    }
}

private enum ISODateParser {
    static func parse(_ raw: String) -> Date? {
        ISO8601DateFormatter.withFractionalSeconds.date(from: raw)
        ?? ISO8601DateFormatter.internetDateTime.date(from: raw)
    }
}
