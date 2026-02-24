import SwiftUI

struct FavoritesView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("homeCityId") private var homeCityId = AppConfig.homeCityDefault

    let cafes: [SunnyCafe]
    let recommendations: [FavoriteRecommendationItem]
    let recommendationStatus: RecommendationDataStatus
    let recommendationFreshnessHours: Double?
    let recommendationProviderUsed: String?
    let recommendationError: String?
    let onRefreshRecommendations: () async -> Void
    let onTapCafe: (SunnyCafe) -> Void
    let onRemoveFavorite: (SunnyCafe) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if cafes.isEmpty {
                    ContentUnavailableView(
                        "No Favorites Yet",
                        systemImage: "heart",
                        description: Text("Tap the heart in a cafe detail card to save favorites.")
                    )
                } else {
                    List {
                        recommendationsSection

                        Section("Saved Favorites") {
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
                TelemetryService.track(
                    "recommendation_impression",
                    properties: [
                        "status": recommendationStatus.rawValue,
                        "count": "\(recommendations.count)"
                    ]
                )
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
                        TelemetryService.track("recommendation_empty_state_seen")
                    }
                if let recommendationError, !recommendationError.isEmpty {
                    Text(recommendationError)
                        .font(.caption2)
                        .foregroundStyle(ThemeColor.muted)
                }
            } else {
                ForEach(recommendations.prefix(6)) { item in
                    Button {
                        if let cafe = cafes.first(where: { $0.id == item.cafeID }) {
                            TelemetryService.track(
                                "recommendation_tapped",
                                properties: ["city_id": homeCityId, "cafe_id": item.cafeID]
                            )
                            onTapCafe(cafe)
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: recommendationSymbol(for: item.condition))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(recommendationTint(for: item.condition))
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
            }
        }
    }

    private func recommendationSymbol(for condition: String) -> String {
        switch condition.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "sunny":
            return "sun.max.fill"
        case "partial":
            return "cloud.sun.fill"
        default:
            return "cloud.fill"
        }
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

private extension String {
    func formattedRecommendationDay() -> String {
        guard let date = ISODateParser.parse(self) else {
            return self
        }
        let calendar = Date.copenhagenCalendar
        let now = Date()
        if calendar.isDate(date, inSameDayAs: now) {
            return "Today"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "Tomorrow"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = TimeZone(identifier: "Europe/Copenhagen")
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: date)
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

private enum ISODateParser {
    static func parse(_ raw: String) -> Date? {
        ISO8601DateFormatter.withFractionalSeconds.date(from: raw)
        ?? ISO8601DateFormatter.internetDateTime.date(from: raw)
    }
}
