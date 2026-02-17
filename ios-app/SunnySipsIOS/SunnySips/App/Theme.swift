import SwiftUI

enum ThemeColor {
    static let accentGold = Color(hex: "#D4AF37")
    static let sunnyGreen = Color(hex: "#4CAF50")
    static let partialAmber = Color(hex: "#FFC107")
    static let shadedRed = Color(hex: "#F44336")
    static let clusterGray = Color(.systemGray3)
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
}

extension UIColor {
    static func markerColor(for fraction: Double) -> UIColor {
        if fraction >= 0.99 { return UIColor(red: 0.298, green: 0.686, blue: 0.314, alpha: 1.0) }
        if fraction <= 0.01 { return UIColor(red: 0.957, green: 0.263, blue: 0.212, alpha: 1.0) }
        return UIColor(red: 1.0, green: 0.757, blue: 0.027, alpha: 1.0)
    }
}
