import SwiftUI

struct FiltersSheetView: View {
    @ObservedObject var viewModel: SunnySipsViewModel

    var body: some View {
        NavigationStack {
            Form {
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
                            Text("Today only (15-minute steps)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            QuarterHourDatePicker(
                                selection: selectedTimeBinding,
                                range: Date.todayRange
                            )
                            .frame(height: 160)
                        }
                    }
                }

                Section("Ranking") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Buckets")
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
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Min score")
                            Spacer()
                            Text("\(Int(viewModel.filters.minScore))")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: minScoreBinding, in: 0 ... 100, step: 5)
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
                    if viewModel.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
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
}
