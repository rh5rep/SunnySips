import SwiftUI

struct CafeRowView: View {
    let cafe: CafeSnapshot
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(bucketColor)
                    .frame(width: 10, height: 10)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 4) {
                    Text(cafe.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    HStack(spacing: 10) {
                        Text(bucketTitle)
                        Text("Sun \(Int(cafe.sunnyFraction * 100))%")
                        Text("Score \(Int(cafe.sunnyScore))")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
                    .padding(.top, 5)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.6))
            )
        }
        .buttonStyle(.plain)
    }

    private var bucketTitle: String {
        switch cafe.resolvedBucket {
        case "sunny": return "Sunny"
        case "partial": return "Partial"
        default: return "Shaded"
        }
    }

    private var bucketColor: Color {
        switch cafe.resolvedBucket {
        case "sunny": return ThemeColor.sun
        case "partial": return ThemeColor.coffee
        default: return ThemeColor.shade
        }
    }
}
