import SwiftUI

enum TimePillTone {
    case primary
    case secondary
    case muted
    case sunny

    var background: Color {
        switch self {
        case .primary:
            return ThemeColor.focusBlue
        case .secondary:
            return Color(dynamicLight: "#8A6A4A", dark: "#304155")
        case .muted:
            return Color(dynamicLight: "#867A6B", dark: "#3C4450")
        case .sunny:
            return Color(dynamicLight: "#2E9D5B", dark: "#2F8A57")
        }
    }
}

enum CompactPillSize {
    case regular
    case small

    var height: CGFloat {
        switch self {
        case .regular: return 34
        case .small: return 30
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .regular: return 12
        case .small: return 10
        }
    }
}

struct CompactPillStyle: ViewModifier {
    let tone: TimePillTone
    let size: CompactPillSize
    let isDisabled: Bool

    func body(content: Content) -> some View {
        content
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.white.opacity(isDisabled ? 0.8 : 1.0))
            .lineLimit(1)
            .minimumScaleFactor(0.9)
            .truncationMode(.tail)
            .padding(.horizontal, size.horizontalPadding)
            .frame(height: size.height)
            .background(
                tone.background.opacity(isDisabled ? 0.4 : 0.92),
                in: Capsule()
            )
            .shadow(color: Color.black.opacity(isDisabled ? 0.0 : 0.16), radius: 2, x: 0, y: 1)
            .accessibilityElement(children: .combine)
    }
}

extension View {
    func compactPillStyle(
        _ tone: TimePillTone = .primary,
        size: CompactPillSize = .regular,
        isDisabled: Bool = false
    ) -> some View {
        modifier(CompactPillStyle(tone: tone, size: size, isDisabled: isDisabled))
    }

    func timePillStyle(
        _ tone: TimePillTone = .primary,
        size: CompactPillSize = .regular,
        isDisabled: Bool = false
    ) -> some View {
        compactPillStyle(tone, size: size, isDisabled: isDisabled)
    }
}
