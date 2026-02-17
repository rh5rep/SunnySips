import SwiftUI

enum ThemeColor {
    static let sun = Color(hex: "#D1A257")
    static let coffee = Color(hex: "#7C6046")
    static let cream = Color(hex: "#F3EBDD")
    static let shade = Color(hex: "#4B5A66")
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
