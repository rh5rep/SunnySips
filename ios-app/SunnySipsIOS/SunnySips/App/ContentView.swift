import SwiftUI
import UIKit

private enum ActiveSheet: Identifiable {
    case list
    case filters
    case favorites
    case detail(SunnyCafe)

    var id: String {
        switch self {
        case .list: return "list"
        case .filters: return "filters"
        case .favorites: return "favorites"
        case .detail(let cafe): return "detail-\(cafe.id)"
        }
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    @AppStorage("theme") private var themeRawValue: String = AppTheme.system.rawValue

    @StateObject private var viewModel = SunnySipsViewModel()
    @State private var listDetent: PresentationDetent = .fraction(0.25)
    @State private var activeSheet: ActiveSheet?

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: themeRawValue) ?? .system
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                CafeMapView(
                    cafes: viewModel.cafes,
                    selectedCafe: $viewModel.selectedCafe,
                    region: $viewModel.mapRegion,
                    locateRequestID: viewModel.locateUserRequestID,
                    use3DMap: viewModel.use3DMap,
                    effectiveCloudCover: viewModel.cloudCoverPct,
                    warningMessage: viewModel.warningMessage,
                    onRegionChanged: { viewModel.mapRegionChanged($0) },
                    onSelectCafe: { viewModel.selectCafeFromMap($0) },
                    onPermissionDenied: { viewModel.locationPermissionDenied() },
                    onUserLocationUpdate: { viewModel.updateUserLocation($0) }
                )
                .ignoresSafeArea(edges: .bottom)

                statsHeader
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))

                mapFloatingControls
                    .padding(.trailing, 12)
                    .padding(.top, 170)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

                if let nonBlockingError = viewModel.errorMessage, viewModel.blockingError == nil {
                    VStack {
                        Spacer()
                        Text(nonBlockingError)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, 18)
                    }
                    .transition(.opacity)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        presentFilters()
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Open filters")
                }

                ToolbarItem(placement: .principal) {
                    Text("SunnySips")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(ThemeColor.coffeeDark)
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        presentFavorites()
                    } label: {
                        Image(systemName: "heart")
                            .imageScale(.medium)
                    }
                    .contextMenu {
                        ForEach(AppTheme.allCases) { theme in
                            Button {
                                themeRawValue = theme.rawValue
                            } label: {
                                Label(theme.title, systemImage: theme.rawValue == themeRawValue ? "checkmark" : "paintpalette")
                            }
                        }
                    }
                    .accessibilityLabel("Open favorites")
                    .accessibilityHint("Long press for theme options")

                    Button {
                        presentList()
                    } label: {
                        Image(systemName: "list.bullet")
                            .imageScale(.medium)
                    }
                    .accessibilityLabel("Open cafe list")
                }
            }
            .task {
                await viewModel.onAppear()
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    viewModel.startAutoRefresh()
                default:
                    viewModel.stopAutoRefresh()
                }
            }
            .onChange(of: viewModel.selectedCafe) { _, cafe in
                guard let cafe else { return }
                activeSheet = .detail(cafe)
            }
            .overlay {
                if viewModel.isInitialLoading {
                    loadingView
                } else if let blockingError = viewModel.blockingError {
                    blockingErrorView(message: blockingError)
                }
            }
            .sheet(item: $activeSheet, onDismiss: {
                viewModel.selectedCafe = nil
            }) { sheet in
                switch sheet {
                case .list:
                    ListSheetView(
                        cafes: viewModel.visibleCafes,
                        totalVisibleCount: viewModel.visibleCafes.count,
                        favoriteCafeIDs: viewModel.favoriteCafeIDs,
                        onTapCafe: { cafe in
                            viewModel.selectCafeFromList(cafe)
                            activeSheet = .detail(cafe)
                        }
                    )
                    .presentationDetents([.fraction(0.25), .medium, .large], selection: $listDetent)
                    .presentationBackgroundInteraction(.enabled)
                    .presentationDragIndicator(.visible)
                    .presentationBackground(ThemeColor.surface)
                    .animation(.spring(response: 0.35, dampingFraction: 0.9), value: listDetent)
                case .filters:
                    FiltersSheetView(viewModel: viewModel)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                        .presentationBackground(ThemeColor.surface)
                case .favorites:
                    FavoritesView(
                        cafes: viewModel.favoriteCafes,
                        onTapCafe: { cafe in
                            viewModel.selectCafeFromList(cafe)
                            activeSheet = .detail(cafe)
                        },
                        onRemoveFavorite: { cafe in
                            viewModel.toggleFavorite(cafe)
                        }
                    )
                    .presentationDetents([.fraction(0.25), .medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(ThemeColor.surface)
                case .detail(let cafe):
                    CafeDetailView(
                        cafe: cafe,
                        isFavorite: Binding(
                            get: { viewModel.isFavorite(cafe) },
                            set: { newValue in
                                let existing = viewModel.isFavorite(cafe)
                                if newValue != existing {
                                    viewModel.toggleFavorite(cafe)
                                }
                            }
                        )
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(ThemeColor.surface)
                }
            }
            .fullScreenCover(isPresented: $viewModel.isFullMapPresented) {
                fullMapView
            }
            .alert("Location Access Needed", isPresented: $viewModel.showLocationSettingsPrompt) {
                Button("Cancel", role: .cancel) {}
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
            } message: {
                Text("Enable location access in Settings to center on your position.")
            }
        }
    }

    private var statsHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.areaTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ThemeColor.ink)

                    Text("\(viewModel.cafes.count) cafes • \(viewModel.updatedRelativeText)")
                        .font(.caption)
                        .foregroundStyle(ThemeColor.muted)
                }

                Spacer()

                Button {
                    Task { await viewModel.refreshTapped() }
                } label: {
                    if viewModel.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .foregroundStyle(ThemeColor.coffeeDark)
                .accessibilityLabel("Refresh cafes")
            }

            HStack(spacing: 8) {
                bucketChip(bucket: .sunny, label: "\(viewModel.stats.sunny)", icon: "sun.max.fill", color: ThemeColor.sunnyGreen)
                bucketChip(bucket: .partial, label: "\(viewModel.stats.partial)", icon: "cloud.sun.fill", color: ThemeColor.partialAmber)
                bucketChip(bucket: .shaded, label: "\(viewModel.stats.shaded)", icon: "cloud.fill", color: ThemeColor.shadedRed)
            }

            if let warning = viewModel.warningMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(ThemeColor.shadedRed)
                    Text(warning)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(ThemeColor.coffeeDark)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(ThemeColor.surfaceSoft.opacity(0.92), in: Capsule())
            }

            HStack {
                Spacer()

                Button {
                    viewModel.togglePredictFutureMode()
                } label: {
                    Text(viewModel.filters.useNow ? "Predict Future" : "Back to Now")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(ThemeColor.sun.opacity(0.25), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(viewModel.filters.useNow ? "Switch to future prediction mode" : "Switch back to now")
            }

            if !viewModel.filters.useNow {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(futureLabel(viewModel.filters.selectedTime))
                        Spacer()
                        Text("+\(Int(viewModel.futureHourOffset))h")
                    }
                    .font(.caption2)
                    .foregroundStyle(ThemeColor.muted)

                    Slider(
                        value: Binding(
                            get: { viewModel.futureHourOffset },
                            set: { viewModel.setFutureHourOffset($0) }
                        ),
                        in: 0 ... 24,
                        step: 1
                    )
                    .tint(ThemeColor.focusBlue)
                    .accessibilityLabel("Prediction timeline")
                    .accessibilityHint("Jump forecast time in one hour steps")
                }
            }
        }
        .padding(12)
        .background(headerBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(ThemeColor.line.opacity(0.5), lineWidth: 1)
        )
    }

    private var mapFloatingControls: some View {
        VStack(spacing: 10) {
            mapControlButton(systemName: "arrow.up.left.and.arrow.down.right", accessibility: "Open full map") {
                withAnimation(.spring(duration: 0.3)) { presentFullMap() }
            }

            mapControlButton(systemName: "location.fill", accessibility: "Center on my location") {
                viewModel.requestLocateUser()
            }

            mapControlButton(
                systemName: viewModel.use3DMap ? "map" : "cube",
                accessibility: viewModel.use3DMap ? "Switch to flat map" : "Switch to 3D map"
            ) {
                viewModel.toggleMapStyle()
            }
        }
    }

    private func mapControlButton(systemName: String, accessibility: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ThemeColor.coffeeDark)
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(ThemeColor.line.opacity(0.55), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
    }

    private var headerBackground: some ShapeStyle {
        if #available(iOS 18.0, *) {
            return AnyShapeStyle(.ultraThinMaterial)
        }
        return AnyShapeStyle(.thinMaterial)
    }

    private func bucketChip(bucket: SunnyBucketFilter, label: String, icon: String, color: Color) -> some View {
        let isSelected = viewModel.filters.selectedBuckets.contains(bucket)

        return Button {
            withAnimation(.spring(duration: 0.22)) {
                viewModel.toggleBucket(bucket)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .foregroundStyle(isSelected ? ThemeColor.surface : color)
                Text(label)
                    .foregroundStyle(isSelected ? ThemeColor.surface : ThemeColor.ink)
            }
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? color.opacity(0.95) : ThemeColor.surface.opacity(0.9))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filter \(bucket.title)")
    }

    private var loadingView: some View {
        ZStack {
            ThemeColor.bg.opacity(0.8)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("Finding sunny cafes...")
                    .font(.headline)
                    .foregroundStyle(ThemeColor.ink)
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func blockingErrorView(message: String) -> some View {
        ZStack {
            ThemeColor.bg.opacity(0.9)
                .ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(ThemeColor.muted)
                Text("Could not load cafes")
                    .font(.title3.weight(.semibold))
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(ThemeColor.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                Button("Retry") {
                    Task { await viewModel.refreshTapped() }
                }
                .buttonStyle(.borderedProminent)
                .tint(ThemeColor.coffee)
            }
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(24)
        }
    }

    private var fullMapView: some View {
        NavigationStack {
            CafeMapView(
                cafes: viewModel.cafes,
                selectedCafe: $viewModel.selectedCafe,
                region: $viewModel.mapRegion,
                locateRequestID: viewModel.locateUserRequestID,
                use3DMap: viewModel.use3DMap,
                effectiveCloudCover: viewModel.cloudCoverPct,
                warningMessage: viewModel.warningMessage,
                onRegionChanged: { viewModel.mapRegionChanged($0) },
                onSelectCafe: { viewModel.selectCafeFromMap($0) },
                onPermissionDenied: { viewModel.locationPermissionDenied() },
                onUserLocationUpdate: { viewModel.updateUserLocation($0) }
            )
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Full Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        viewModel.isFullMapPresented = false
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        viewModel.toggleMapStyle()
                    } label: {
                        Image(systemName: viewModel.use3DMap ? "map" : "cube")
                    }

                    Button {
                        viewModel.requestLocateUser()
                    } label: {
                        Image(systemName: "location.fill")
                    }
                    Button {
                        viewModel.isFullMapPresented = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            presentList()
                        }
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                }
            }
        }
    }

    private func presentFilters() {
        viewModel.selectedCafe = nil
        activeSheet = .filters
    }

    private func presentList() {
        viewModel.selectedCafe = nil
        activeSheet = .list
    }

    private func presentFavorites() {
        viewModel.selectedCafe = nil
        activeSheet = .favorites
    }

    private func presentFullMap() {
        viewModel.selectedCafe = nil
        activeSheet = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            viewModel.isFullMapPresented = true
        }
    }

    private func futureLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Date.copenhagenCalendar
        formatter.timeZone = TimeZone(identifier: "Europe/Copenhagen")
        formatter.dateFormat = "EEE HH:mm"
        return formatter.string(from: date)
    }
}
