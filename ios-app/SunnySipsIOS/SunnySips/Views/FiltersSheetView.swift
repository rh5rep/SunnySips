import SwiftUI

struct FiltersSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: SunnySipsViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Quick Presets") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(SunnyQuickPreset.allCases) { preset in
                                Button(preset.title) {
                                    viewModel.applyQuickPreset(preset)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Area") {
                    Picker("Neighborhood", selection: areaBinding) {
                        ForEach(SunnyArea.allCases) { area in
                            Text(area.title).tag(area)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section("Time") {
                    Toggle("Use Now", isOn: useNowBinding)

                    if !viewModel.filters.useNow {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Now through +24 hours (15-minute steps)")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    jumpButton("Now +1h", minutes: 60)
                                    jumpButton("+3h", minutes: 180)
                                    jumpButton("+6h", minutes: 360)
                                    jumpButton("+12h", minutes: 720)
                                    jumpButton("+24h", minutes: 1440)
                                }
                                .padding(.vertical, 2)
                            }

                            QuarterHourDatePicker(
                                selection: selectedTimeBinding,
                                range: viewModel.predictionRange
                            )
                            .frame(height: 190)
                        }
                    }
                }

                Section("Ranking") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Conditions")
                            .font(.subheadline.weight(.semibold))

                        HStack(spacing: 8) {
                            ForEach(SunnyBucketFilter.allCases) { bucket in
                                let selected = viewModel.filters.selectedBuckets.contains(bucket)
                                Button {
                                    viewModel.toggleBucket(bucket)
                                } label: {
                                    Text(bucket.title)
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule().fill(selected ? color(for: bucket).opacity(0.88) : Color(.systemBackground).opacity(0.55))
                                        )
                                        .foregroundStyle(selected ? Color.black : Color.primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if let warning = viewModel.warningMessage {
                            Text(warning)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }

                    Toggle("Favorites Only", isOn: favoritesOnlyBinding)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Min score")
                            Spacer()
                            Text("\(Int(viewModel.filters.minScore))")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: minScoreBinding, in: 0 ... 100, step: 5)
                            .accessibilityLabel("Minimum score")
                            .accessibilityHint("Adjust minimum sunny score")
                    }

                    TextField(
                        "Search name",
                        text: searchBinding,
                        prompt: Text("Coffee Collective")
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    Picker("Sort", selection: sortBinding) {
                        ForEach(SunnySortOption.allCases) { sort in
                            Text(sort.title).tag(sort)
                        }
                    }
                }

                Section {
                    Button("Reset Filters", role: .destructive) {
                        viewModel.resetFilters()
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 10) {
                        if viewModel.isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Button("Close") {
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private var areaBinding: Binding<SunnyArea> {
        Binding(
            get: { viewModel.filters.area },
            set: { viewModel.areaChanged($0) }
        )
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

    private var sortBinding: Binding<SunnySortOption> {
        Binding(
            get: { viewModel.filters.sort },
            set: { viewModel.sortChanged($0) }
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
        Button(title) {
            withAnimation(.spring(duration: 0.2)) {
                viewModel.jumpForward(minutes: minutes)
            }
        }
        .buttonStyle(.bordered)
        .font(.caption.weight(.semibold))
        .disabled(!viewModel.canJumpForward(minutes: minutes))
        .accessibilityLabel("Jump forward \(minutes >= 60 ? "\(minutes / 60) hours" : "\(minutes) minutes")")
    }
}
