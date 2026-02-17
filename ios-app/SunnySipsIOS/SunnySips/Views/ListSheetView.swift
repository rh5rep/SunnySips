import SwiftUI

struct ListSheetView: View {
    let cafes: [SunnyCafe]
    let totalVisibleCount: Int
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
                    List(cafes) { cafe in
                        CafeRowView(cafe: cafe) {
                            onTapCafe(cafe)
                        }
                        .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Visible Cafes (\(totalVisibleCount))")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
