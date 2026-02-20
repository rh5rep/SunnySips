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
    static let bg = Color(dynamicLight: "#F3ECE2", dark: "#111111")
    static let surface = Color(dynamicLight: "#FBF6EE", dark: "#1A1A1A")
    static let surfaceSoft = Color(dynamicLight: "#ECE1D2", dark: "#25201B")

    static let coffee = Color(dynamicLight: "#8B725C", dark: "#BFA58E")
    static let coffeeDark = Color(dynamicLight: "#5A4738", dark: "#E8D7C4")
    static let sun = Color(dynamicLight: "#E1C46F", dark: "#F0D586")
    static let sunBright = Color(dynamicLight: "#F0D78F", dark: "#FFE3A7")

    static let ink = Color(dynamicLight: "#2F2A25", dark: "#F5F1E8")
    static let muted = Color(dynamicLight: "#796A5C", dark: "#B8AA9A")
    static let line = Color(dynamicLight: "#D4C3AD", dark: "#3A322B")

    static let sunnyGreen = Color(dynamicLight: "#2E9D5B", dark: "#6FD98A")
    static let partialAmber = Color(dynamicLight: "#D89A28", dark: "#F0C05F")
    static let shadedRed = Color(dynamicLight: "#D9534F", dark: "#FF7E79")

    static let focusBlue = Color(dynamicLight: "#4A82D7", dark: "#78AAFA")
    static let clusterGray = Color(dynamicLight: "#72675D", dark: "#9D9288")

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
