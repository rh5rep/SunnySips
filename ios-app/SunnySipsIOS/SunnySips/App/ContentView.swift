import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = SunnySipsViewModel()
    @State private var displayMode: DisplayMode = .split

    enum DisplayMode: String, CaseIterable, Identifiable {
        case split
        case map
        case list

        var id: String { rawValue }
        var title: String {
            switch self {
            case .split: return "Split"
            case .map: return "Map"
            case .list: return "List"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.snapshotIndex == nil {
                    ProgressView("Loading snapshots...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            controlsCard
                            summaryCard
                            contentSection
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
            .background(ThemeColor.cream.opacity(0.25))
            .navigationTitle("SunnySips")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh snapshots")
                }
            }
            .task {
                await viewModel.loadIfNeeded()
            }
            .refreshable {
                await viewModel.refresh()
            }
            .alert(
                "Snapshot Error",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { isPresented in
                        if !isPresented {
                            viewModel.errorMessage = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "Unknown error")
            }
            .sheet(item: $viewModel.selectedCafe) { cafe in
                CafeDetailView(cafe: cafe)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Where & When")
                .font(.headline)

            Picker("Area", selection: $viewModel.selectedArea) {
                ForEach(viewModel.availableAreas) { area in
                    Text(viewModel.displayName(for: area.area)).tag(area.area)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: viewModel.selectedArea) { _, newValue in
                viewModel.didSelectArea(newValue)
            }

            HStack {
                Menu {
                    ForEach(viewModel.availableTimeSnapshots) { snapshot in
                        Button(snapshot.localTimeLabel) {
                            viewModel.selectedTimeUTC = snapshot.timeUTC
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "clock")
                        Text(viewModel.activeTimeSnapshot?.localTimeLabel ?? "Select time")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.availableTimeSnapshots.isEmpty)

                Button("Now") {
                    viewModel.selectNow()
                }
                .buttonStyle(.borderedProminent)
            }

            Divider()

            Text("Filters")
                .font(.headline)

            Picker("Bucket", selection: $viewModel.selectedBucket) {
                ForEach(BucketFilter.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)

            TextField("Search cafes", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)

            Toggle("Hide fully shaded", isOn: $viewModel.hideShaded)

            Picker("Sort", selection: $viewModel.sortOrder) {
                ForEach(SortOrder.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Min score")
                    Spacer()
                    Text("\(Int(viewModel.minScore))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $viewModel.minScore, in: 0 ... 100, step: 1)
            }

            HStack {
                Picker("View", selection: $displayMode) {
                    ForEach(DisplayMode.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                Button("Reset") {
                    viewModel.resetFilters()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(viewModel.displayName(for: viewModel.selectedArea))
                    .font(.headline)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(viewModel.filteredCafes.count) cafes")
                        .font(.subheadline)
                    if let updated = viewModel.lastUpdatedText {
                        Text(updated)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let snapshot = viewModel.activeTimeSnapshot {
                HStack(spacing: 14) {
                    Label("\(snapshot.summary.sunny) sunny", systemImage: "sun.max.fill")
                        .foregroundStyle(ThemeColor.sun)
                    Label("\(snapshot.summary.partial) partial", systemImage: "sun.haze.fill")
                        .foregroundStyle(ThemeColor.coffee)
                    Label("\(snapshot.summary.shaded) shaded", systemImage: "moon.stars.fill")
                        .foregroundStyle(ThemeColor.shade)
                }
                .font(.caption)

                HStack {
                    Text("Cloud \(Int(snapshot.cloudCoverPct))%")
                    Spacer()
                    Text("Avg score \(Int(snapshot.summary.avgScore))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var contentSection: some View {
        switch displayMode {
        case .map:
            mapCard
        case .list:
            listCard
        case .split:
            VStack(spacing: 14) {
                mapCard
                listCard
            }
        }
    }

    private var mapCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Map")
                .font(.headline)
            CafeMapView(cafes: viewModel.filteredCafes, selectedCafe: $viewModel.selectedCafe)
                .frame(height: 340)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var listCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cafes")
                .font(.headline)
            if viewModel.filteredCafes.isEmpty {
                Text("No cafes match this filter.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.filteredCafes) { cafe in
                        CafeRowView(cafe: cafe) {
                            viewModel.selectedCafe = cafe
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
