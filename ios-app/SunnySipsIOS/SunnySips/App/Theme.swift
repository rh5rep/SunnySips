import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum ThemeColor {
    static let bg = Color(dynamicLight: "#F6F2E9", dark: "#111111")
    static let surface = Color(dynamicLight: "#FFFDF8", dark: "#1A1A1A")
    static let surfaceSoft = Color(dynamicLight: "#F1E9DB", dark: "#242424")

    static let coffee = Color(dynamicLight: "#8A6A4A", dark: "#B59577")
    static let coffeeDark = Color(dynamicLight: "#5E4733", dark: "#E5CCB1")
    static let sun = Color(dynamicLight: "#E5C36A", dark: "#F2D67C")
    static let sunBright = Color(dynamicLight: "#F2D67C", dark: "#FFDFA3")

    static let ink = Color(dynamicLight: "#2F2A25", dark: "#F5F1E8")
    static let muted = Color(dynamicLight: "#6E6459", dark: "#B7ADA1")
    static let line = Color(dynamicLight: "#D9CCB5", dark: "#3A332B")

    static let sunnyGreen = Color(dynamicLight: "#2E9D5B", dark: "#6FD98A")
    static let partialAmber = Color(dynamicLight: "#D89A28", dark: "#F0C05F")
    static let shadedRed = Color(dynamicLight: "#D9534F", dark: "#FF7E79")

    static let focusBlue = Color(dynamicLight: "#3A7BD5", dark: "#74A7F5")
    static let clusterGray = Color(dynamicLight: "#6F6C66", dark: "#9A9690")

    static let accentGold = sun
}

extension Color {
    init(hex: String) {
        let clean = hex.replacingOccurrences(of: "#", with: "")
        var value: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }

    init(dynamicLight lightHex: String, dark darkHex: String) {
        self.init(
            UIColor { trait in
                if trait.userInterfaceStyle == .dark {
                    return UIColor(hex: darkHex)
                }
                return UIColor(hex: lightHex)
            }
        )
    }
}

extension UIColor {
    convenience init(hex: String) {
        let clean = hex.replacingOccurrences(of: "#", with: "")
        var value: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&value)
        let r = CGFloat((value >> 16) & 0xFF) / 255.0
        let g = CGFloat((value >> 8) & 0xFF) / 255.0
        let b = CGFloat(value & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }

    static func markerColor(for fraction: Double) -> UIColor {
        if fraction >= 0.99 { return UIColor(hex: "#2E9D5B") }
        if fraction <= 0.01 { return UIColor(hex: "#D9534F") }
        return UIColor(hex: "#D89A28")
    }
}
