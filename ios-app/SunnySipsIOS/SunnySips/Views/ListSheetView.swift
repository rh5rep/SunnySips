import SwiftUI

struct ListSheetView: View {
    @Environment(\.dismiss) private var dismiss

    let cafes: [SunnyCafe]
    let totalVisibleCount: Int
    let favoriteCafeIDs: Set<String>
    let onTapCafe: (SunnyCafe) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if cafes.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "map")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("No cafes in current map view")
                            .font(.headline)
                        Text("Move or zoom the map to see cafes here.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(24)
                } else {
                    VStack(spacing: 0) {
                        HStack {
                            Text("Showing \(cafes.count) of \(totalVisibleCount) visible cafes")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("Drag up for more")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                        List(cafes) { cafe in
                            CafeRowView(cafe: cafe, isFavorite: favoriteCafeIDs.contains(cafe.id)) {
                                onTapCafe(cafe)
                            }
                            .listRowSeparator(.hidden)
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .navigationTitle("Visible Cafes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                    .accessibilityLabel("Close list")
                }
            }
        }
    }
}
