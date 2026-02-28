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

enum MapDensity: String, CaseIterable, Identifiable {
    case focused
    case balanced
    case dense

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focused: return "Focused"
        case .balanced: return "Balanced"
        case .dense: return "Dense"
        }
    }

    var subtitle: String {
        switch self {
        case .focused: return "Fewer map markers, calmer view"
        case .balanced: return "Default mix of coverage and clarity"
        case .dense: return "Show more cafes at each zoom level"
        }
    }

    var annotationBudgetMultiplier: Double {
        switch self {
        case .focused: return 0.78
        case .balanced: return 1.0
        case .dense: return 1.28
        }
    }
}

enum ThemeColor {
    static let bg = Color(dynamicLight: "#F2E9DE", dark: "#17120F")
    static let surface = Color(dynamicLight: "#FBF5EC", dark: "#1F1915")
    static let surfaceSoft = Color(dynamicLight: "#E7DACB", dark: "#2A211C")

    static let coffee = Color(dynamicLight: "#9A6A52", dark: "#C89F83")
    static let coffeeDark = Color(dynamicLight: "#5C3D2E", dark: "#F0E2D4")
    static let sun = Color(dynamicLight: "#D7B071", dark: "#E6C38E")
    static let sunBright = Color(dynamicLight: "#EACB95", dark: "#F4D7A8")

    static let ink = Color(dynamicLight: "#31261F", dark: "#F6EEE5")
    static let muted = Color(dynamicLight: "#8A7765", dark: "#BBA896")
    static let line = Color(dynamicLight: "#D7C6B4", dark: "#473A31")

    static let sunnyGreen = Color(dynamicLight: "#B07B2E", dark: "#D0A35C")
    static let partialAmber = Color(dynamicLight: "#C39A66", dark: "#DEBC8B")
    static let shadedRed = Color(dynamicLight: "#9D685B", dark: "#C89082")

    static let focusBlue = Color(dynamicLight: "#8A5D47", dark: "#C79A79")
    static let clusterGray = Color(dynamicLight: "#7C6B5E", dark: "#A39284")

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
        if fraction >= 0.99 { return UIColor(hex: "#B07B2E") }
        if fraction <= 0.01 { return UIColor(hex: "#9D685B") }
        return UIColor(hex: "#C39A66")
    }
}
