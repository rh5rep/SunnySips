import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @StateObject private var viewModel = SunnySipsViewModel()
    @State private var selectedTab: AppTab = .map
    @State private var showFilters = false
    @State private var showFullMap = false
    @State private var showLocationSettingsAlert = false
    @State private var locateRequestID = 0

    enum AppTab: String, Hashable {
        case map
        case list
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.snapshotIndex == nil {
                    ProgressView("Loading snapshots...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 10) {
                        summaryCard
                            .padding(.horizontal, 16)
                            .padding(.top, 10)
                        tabSection
                            .padding(.horizontal, 8)
                            .padding(.bottom, 4)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .background(ThemeColor.cream.opacity(0.25))
            .navigationTitle("SunnySips")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showFilters = true
                    } label: {
                        Label("Filters", systemImage: "slider.horizontal.3")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            selectedTab = .map
                            locateRequestID += 1
                        } label: {
                            Image(systemName: "location.fill")
                        }
                        .accessibilityLabel("Locate me")

                        Button {
                            Task { await viewModel.refresh() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("Refresh snapshots")
                    }
                }
            }
            .task {
                await viewModel.loadIfNeeded()
                viewModel.startAutoRefresh()
            }
            .onDisappear {
                viewModel.stopAutoRefresh()
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .active:
                    viewModel.startAutoRefresh()
                default:
                    viewModel.stopAutoRefresh()
                }
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
            .sheet(isPresented: $showFilters) {
                filterSheet
            }
            .fullScreenCover(isPresented: $showFullMap) {
                NavigationStack {
                    CafeMapView(
                        cafes: viewModel.filteredCafes,
                        selectedCafe: $viewModel.selectedCafe,
                        locateRequestID: locateRequestID
                    ) {
                        showLocationSettingsAlert = true
                    }
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle("Full Map")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close") {
                                showFullMap = false
                            }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                locateRequestID += 1
                            } label: {
                                Image(systemName: "location.fill")
                            }
                        }
                    }
                }
            }
            .alert("Location Access Disabled", isPresented: $showLocationSettingsAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
            } message: {
                Text("Enable location in iPhone Settings to center the map on your position.")
            }
        }
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

            HStack {
                Text("Time: \(viewModel.activeTimeSnapshot?.localTimeLabel ?? "Unknown")")
                Spacer()
                Text("\(viewModel.availableTimeSnapshots.count) forecast slots")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

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

    private var tabSection: some View {
        TabView(selection: $selectedTab) {
            mapCard
                .tabItem { Label("Map", systemImage: "map.fill") }
                .tag(AppTab.map)

            listCard
                .tabItem { Label("List", systemImage: "list.bullet") }
                .tag(AppTab.list)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mapCard: some View {
        ZStack(alignment: .topTrailing) {
            CafeMapView(
                cafes: viewModel.filteredCafes,
                selectedCafe: $viewModel.selectedCafe,
                locateRequestID: locateRequestID
            ) {
                showLocationSettingsAlert = true
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))

            Button {
                showFullMap = true
            } label: {
                Label("Full Map", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .padding(10)
        }
        .padding(.horizontal, 8)
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
                List(viewModel.filteredCafes) { cafe in
                    CafeRowView(cafe: cafe) {
                        viewModel.selectedCafe = cafe
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
            }
        }
        .padding(10)
    }

    private var filterSheet: some View {
        NavigationStack {
            Form {
                Section("Where & When") {
                    Picker("Area", selection: $viewModel.selectedArea) {
                        ForEach(viewModel.availableAreas) { area in
                            Text(viewModel.displayName(for: area.area)).tag(area.area)
                        }
                    }
                    .onChange(of: viewModel.selectedArea) { _, newValue in
                        viewModel.didSelectArea(newValue)
                    }

                    Picker("Time", selection: $viewModel.selectedTimeUTC) {
                        ForEach(viewModel.availableTimeSnapshots) { snapshot in
                            Text(snapshot.localTimeLabel).tag(Optional(snapshot.timeUTC))
                        }
                    }
                    .disabled(viewModel.availableTimeSnapshots.isEmpty)

                    Button("Use Now") {
                        viewModel.selectNow()
                    }
                }

                Section("Filters") {
                    Picker("Bucket", selection: $viewModel.selectedBucket) {
                        ForEach(BucketFilter.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }

                    TextField("Search cafes", text: $viewModel.searchText)

                    Toggle("Hide fully shaded", isOn: $viewModel.hideShaded)

                    Picker("Sort", selection: $viewModel.sortOrder) {
                        ForEach(SortOrder.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }

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
                }

                Section {
                    Button("Reset Filters") {
                        viewModel.resetFilters()
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showFilters = false
                    }
                }
            }
        }
    }
}
