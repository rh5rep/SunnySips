import SwiftUI

struct CafeRowView: View {
    let cafe: SunnyCafe
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Circle()
                    .fill(markerColor)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 4) {
                    Text(cafe.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text("Sunny \(cafe.sunnyPercent)%   Score \(Int(cafe.sunnyScore))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(cafe.name). Sunny \(cafe.sunnyPercent) percent. Score \(Int(cafe.sunnyScore)).")
        .accessibilityHint("Centers map and opens details")
    }

    private var markerColor: Color {
        switch cafe.bucket {
        case .sunny: return ThemeColor.sunnyGreen
        case .partial: return ThemeColor.partialAmber
        case .shaded: return ThemeColor.shadedRed
        }
    }
}
