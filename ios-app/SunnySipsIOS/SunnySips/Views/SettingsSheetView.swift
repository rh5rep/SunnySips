import SwiftUI

struct SettingsSheetView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var theme: AppTheme
    @Binding var use3DMap: Bool
    @Binding var mapDensity: MapDensity

    let onReplayTutorial: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    appearanceCard
                    mapCard
                    helpCard
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .background(ThemeColor.bg.opacity(0.45).ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundStyle(ThemeColor.accentGold)
                }
            }
        }
    }

    private var appearanceCard: some View {
        sectionCard(title: "Appearance", subtitle: "Store app-wide look and feel") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Theme")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ThemeColor.ink)

                Picker("Theme", selection: $theme) {
                    ForEach(AppTheme.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                Text(themeDescription)
                    .font(.caption)
                    .foregroundStyle(ThemeColor.muted)
            }
        }
    }

    private var mapCard: some View {
        sectionCard(title: "Map", subtitle: "Control map feel and performance") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("3D Map")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ThemeColor.ink)
                        Text("Switch between flat and depth-based map rendering.")
                            .font(.caption)
                            .foregroundStyle(ThemeColor.muted)
                    }
                    Spacer(minLength: 8)
                    Toggle("", isOn: $use3DMap)
                        .labelsHidden()
                        .tint(ThemeColor.focusBlue)
                }

                Divider()
                    .overlay(ThemeColor.line.opacity(0.55))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Map density")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ThemeColor.ink)

                    Picker("Map density", selection: $mapDensity) {
                        ForEach(MapDensity.allCases) { density in
                            Text(density.title).tag(density)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(mapDensity.subtitle)
                        .font(.caption)
                        .foregroundStyle(ThemeColor.muted)
                }
            }
        }
    }

    private var helpCard: some View {
        sectionCard(title: "Help", subtitle: "Guidance and product setup") {
            Button {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    onReplayTutorial()
                }
            } label: {
                Label("Replay app tutorial", systemImage: "play.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(ThemeColor.focusBlue, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var themeDescription: String {
        switch theme {
        case .system:
            return "Follow the device appearance automatically."
        case .light:
            return "Keep SunnySips bright and airy all day."
        case .dark:
            return "Use the darker app appearance consistently."
        }
    }

    private func sectionCard<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(0.7)
                    .foregroundStyle(ThemeColor.muted)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(ThemeColor.muted.opacity(0.9))
            }

            content()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(ThemeColor.surface.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(ThemeColor.line.opacity(0.45), lineWidth: 1)
        )
    }
}
