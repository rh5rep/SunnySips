import SwiftUI

struct CafeRowView: View {
    let cafe: SunnyCafe
    let isFavorite: Bool
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

                    Text("\(condition.emoji) \(condition.rawValue)   Score \(cafe.scoreString)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ThemeColor.accentGold)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(cafe.name). \(condition.rawValue) adjusted for weather. Score \(cafe.scoreString).")
        .accessibilityHint("Centers map and opens details")
    }

    private var markerColor: Color {
        condition.color
    }

    private var condition: EffectiveCondition {
        cafe.effectiveCondition
    }
}
