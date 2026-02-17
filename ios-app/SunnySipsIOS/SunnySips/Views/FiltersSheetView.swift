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
                    Picker("Bucket", selection: bucketBinding) {
                        ForEach(SunnyBucketFilter.allCases) { bucket in
                            Text(bucket.title).tag(bucket)
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

    private var bucketBinding: Binding<SunnyBucketFilter> {
        Binding(
            get: { viewModel.filters.bucket },
            set: { viewModel.bucketChanged($0) }
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
}
