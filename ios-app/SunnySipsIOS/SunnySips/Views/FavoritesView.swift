import SwiftUI

struct FavoritesView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("homeCityId") private var homeCityId = AppConfig.homeCityDefault

    let cafes: [SunnyCafe]
    let recommendations: [FavoriteRecommendationItem]
    let recommendationStatus: RecommendationDataStatus
    let recommendationFreshnessHours: Double?
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
            if recommendationStatus == .stale, let freshness = recommendationFreshnessHours {
                Text("Using \(Int(freshness.rounded()))h old data")
                    .font(.footnote)
                    .foregroundStyle(ThemeColor.muted)
            }

            if recommendations.isEmpty {
                Text("No recommendations right now.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .onAppear {
                        TelemetryService.track("recommendation_empty_state_seen")
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
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.cafeName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ThemeColor.ink)
                            Text("\(item.startLocal.formattedTimeOnly()) - \(item.endLocal.formattedTimeOnly()) • \(item.condition.capitalized) • \(item.durationMin)m")
                                .font(.caption)
                                .foregroundStyle(ThemeColor.muted)
                            Text(item.reason)
                                .font(.caption2)
                                .foregroundStyle(ThemeColor.muted)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private extension String {
    func formattedTimeOnly() -> String {
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
}
