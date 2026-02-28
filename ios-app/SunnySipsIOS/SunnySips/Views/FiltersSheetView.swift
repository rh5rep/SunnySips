import SwiftUI

struct FiltersSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: SunnySipsViewModel

    let onReplayTutorial: () -> Void

    @FocusState private var searchFocused: Bool

    init(viewModel: SunnySipsViewModel, onReplayTutorial: @escaping () -> Void = {}) {
        self.viewModel = viewModel
        self.onReplayTutorial = onReplayTutorial
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    quickPresetsCard
                    areaCard
                    timeCard
                    rankingCard
                    utilitiesCard
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(ThemeColor.bg.opacity(0.45).ignoresSafeArea())
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        viewModel.resetFilters()
                    }
                    .foregroundStyle(ThemeColor.shadedRed)
                    .accessibilityLabel("Reset filters")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 10) {
                        if viewModel.isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Button("Close") {
                            dismiss()
                        }
                        .foregroundStyle(ThemeColor.accentGold)
                    }
                }
            }
        }
    }

    private var quickPresetsCard: some View {
        sectionCard(title: "Quick Presets", subtitle: "Apply a ready-made filter set") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SunnyQuickPreset.allCases) { preset in
                        Button {
                            viewModel.applyQuickPreset(preset)
                        } label: {
                            Text(preset.title)
                                .font(.footnote.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.9)
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .background(ThemeColor.sun.opacity(0.95), in: Capsule())
                                .foregroundStyle(ThemeColor.ink)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var areaCard: some View {
        sectionCard(title: "Area", subtitle: "Neighborhood scope") {
            HStack(spacing: 10) {
                Label("Neighborhood", systemImage: "map")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ThemeColor.ink)
                Spacer(minLength: 8)
                Menu {
                    ForEach(SunnyArea.allCases) { area in
                        Button {
                            viewModel.areaChanged(area)
                        } label: {
                            if viewModel.filters.area == area {
                                Label(area.title, systemImage: "checkmark")
                            } else {
                                Text(area.title)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(viewModel.filters.area.title)
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(ThemeColor.coffeeDark)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(ThemeColor.surfaceSoft, in: Capsule())
                }
            }
        }
    }

    private var timeCard: some View {
        sectionCard(title: "Time", subtitle: "Now or forecast up to +24h") {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Label("Use Now", systemImage: "clock")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ThemeColor.ink)
                    Spacer(minLength: 0)
                    Toggle("", isOn: useNowBinding)
                        .labelsHidden()
                        .tint(ThemeColor.focusBlue)
                }

                if !viewModel.filters.useNow {
                    HStack(spacing: 8) {
                        Label("Forecast \(viewModel.selectedForecastTimeText)", systemImage: "clock.badge.checkmark")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(ThemeColor.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(ThemeColor.sun.opacity(0.18), in: Capsule())
                        Spacer(minLength: 0)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            jumpButton("+30m", minutes: 30)
                            jumpButton("+1h", minutes: 60)
                            jumpButton("+2h", minutes: 120)
                            jumpButton("+3h", minutes: 180)
                            jumpButton("+6h", minutes: 360)
                            jumpButton("+12h", minutes: 720)
                        }
                    }

                    QuarterHourDatePicker(
                        selection: selectedTimeBinding,
                        range: viewModel.predictionRange
                    )
                    .frame(height: 188)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(ThemeColor.surfaceSoft.opacity(0.88))
                    )
                    .clipped()
                }
            }
        }
    }

    private var rankingCard: some View {
        sectionCard(title: "Ranking", subtitle: "Score and visibility filters") {
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Conditions")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ThemeColor.ink)

                    Text("Select one or more buckets")
                        .font(.caption)
                        .foregroundStyle(ThemeColor.muted)

                    HStack(spacing: 10) {
                        ForEach(SunnyBucketFilter.allCases) { bucket in
                            bucketChip(bucket)
                        }
                    }
                }

                if let warning = viewModel.warningMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(ThemeColor.shadedRed)
                        Text(warning)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ThemeColor.muted)
                        Spacer()
                    }
                }

                rowSeparator

                HStack {
                    Text("Favorites only")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ThemeColor.ink)
                    Spacer()
                    Toggle("", isOn: favoritesOnlyBinding)
                        .labelsHidden()
                        .tint(ThemeColor.focusBlue)
                }

                rowSeparator

                VStack(spacing: 8) {
                    HStack {
                        Text("Minimum score")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ThemeColor.ink)
                        Spacer()
                        Text("\(Int(viewModel.filters.minScore))")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(ThemeColor.coffeeDark)
                    }
                    Slider(value: minScoreBinding, in: 0 ... 100, step: 5)
                        .tint(ThemeColor.focusBlue)
                        .accessibilityLabel("Minimum score")
                        .accessibilityHint("Adjust minimum sunny score")
                }

                rowSeparator

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(ThemeColor.muted)
                    TextField("Search cafe name", text: searchBinding)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($searchFocused)
                }
                .font(.subheadline)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(ThemeColor.surfaceSoft.opacity(0.85), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                rowSeparator

                HStack {
                    Text("Sort")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ThemeColor.ink)
                    Spacer()
                    Menu {
                        ForEach(SunnySortOption.allCases) { sort in
                            Button {
                                viewModel.sortChanged(sort)
                            } label: {
                                if viewModel.filters.sort == sort {
                                    Label(sort.title, systemImage: "checkmark")
                                } else {
                                    Text(sort.title)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(viewModel.filters.sort.title)
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption.weight(.bold))
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ThemeColor.coffeeDark)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(ThemeColor.surfaceSoft, in: Capsule())
                    }
                }
            }
        }
    }

    private var utilitiesCard: some View {
        sectionCard(title: "Help", subtitle: "Guidance") {
            VStack(spacing: 10) {
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
                .fill(
                    LinearGradient(
                        colors: [ThemeColor.surface.opacity(0.98), ThemeColor.surfaceSoft.opacity(0.88)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(ThemeColor.line.opacity(0.45), lineWidth: 1)
        )
    }

    private var rowSeparator: some View {
        Divider()
            .overlay(ThemeColor.line.opacity(0.55))
    }

    private func bucketChip(_ bucket: SunnyBucketFilter) -> some View {
        let selected = viewModel.filters.selectedBuckets.contains(bucket)
        let tint = color(for: bucket)
        let count = bucketCount(bucket)
        let symbol = bucketSymbol(bucket)

        return Button {
            viewModel.toggleBucket(bucket)
        } label: {
            VStack(spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: symbol)
                        .font(.caption.weight(.semibold))
                    Text("\(count)")
                        .font(.caption.weight(.bold))
                }
                Text(bucket.title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(selected ? .white : ThemeColor.ink)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? tint : ThemeColor.surface.opacity(0.96))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(selected ? tint.opacity(0.18) : ThemeColor.line.opacity(0.42), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(bucket.title), \(count) cafes")
    }

    private func bucketCount(_ bucket: SunnyBucketFilter) -> Int {
        switch bucket {
        case .sunny: return viewModel.stats.sunny
        case .partial: return viewModel.stats.partial
        case .shaded: return viewModel.stats.shaded
        }
    }

    private func bucketSymbol(_ bucket: SunnyBucketFilter) -> String {
        switch bucket {
        case .sunny: return "sun.max.fill"
        case .partial: return "cloud.sun.fill"
        case .shaded: return "cloud.fill"
        }
    }

    private var useNowBinding: Binding<Bool> {
        Binding(
            get: { viewModel.filters.useNow },
            set: { viewModel.useNowChanged($0) }
        )
    }

    private var selectedTimeBinding: Binding<Date> {
        Binding(
            get: { viewModel.filters.selectedTime },
            set: { viewModel.timeChanged($0) }
        )
    }

    private var favoritesOnlyBinding: Binding<Bool> {
        Binding(
            get: { viewModel.filters.favoritesOnly },
            set: { viewModel.favoritesOnlyChanged($0) }
        )
    }

    private var minScoreBinding: Binding<Double> {
        Binding(
            get: { viewModel.filters.minScore },
            set: { viewModel.minScoreChanged($0) }
        )
    }

    private var searchBinding: Binding<String> {
        Binding(
            get: { viewModel.filters.searchText },
            set: { viewModel.searchChanged($0) }
        )
    }

    private func color(for bucket: SunnyBucketFilter) -> Color {
        switch bucket {
        case .sunny: return ThemeColor.sunnyGreen
        case .partial: return ThemeColor.partialAmber
        case .shaded: return ThemeColor.shadedRed
        }
    }

    private func jumpButton(_ title: String, minutes: Int) -> some View {
        let enabled = viewModel.canJumpForward(minutes: minutes)
        return Button {
            withAnimation(.spring(duration: 0.2)) {
                viewModel.jumpForward(minutes: minutes)
            }
        } label: {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(enabled ? .white : ThemeColor.surface.opacity(0.78))
                .lineLimit(1)
                .padding(.horizontal, 11)
                .frame(height: 30)
                .background(
                    Capsule()
                        .fill(enabled ? ThemeColor.focusBlue : ThemeColor.clusterGray.opacity(0.42))
                )
                .overlay(
                    Capsule()
                        .stroke(enabled ? ThemeColor.focusBlue.opacity(0.18) : ThemeColor.line.opacity(0.28), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel("Jump forward \(minutes >= 60 ? "\(minutes / 60) hours" : "\(minutes) minutes")")
    }
}
