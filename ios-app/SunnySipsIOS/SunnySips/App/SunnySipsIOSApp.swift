import SwiftUI

@main
struct SunnySipsIOSApp: App {
    @AppStorage("theme") private var themeRawValue: String = AppTheme.system.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(ThemeColor.accentGold)
                .preferredColorScheme(AppTheme(rawValue: themeRawValue)?.preferredColorScheme)
        }
    }
}
