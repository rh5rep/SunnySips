import SwiftUI

struct FavoritesView: View {
    @Environment(\.dismiss) private var dismiss

    let cafes: [SunnyCafe]
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
                    List(cafes) { cafe in
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
        }
    }
}
