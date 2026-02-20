import SwiftUI
import UIKit

private enum ActiveSheet: Identifiable {
    case list
    case filters
    case favorites
    case forecastTime
    case detail(SunnyCafe)

    var id: String {
        switch self {
        case .list: return "list"
        case .filters: return "filters"
        case .favorites: return "favorites"
        case .forecastTime: return "forecast-time"
        case .detail(let cafe): return "detail-\(cafe.id)"
        }
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    @AppStorage("theme") private var themeRawValue: String = AppTheme.system.rawValue
    @AppStorage("hasSeenOnboardingV1") private var hasSeenOnboardingV1 = false

    @StateObject private var viewModel = SunnySipsViewModel()
    @State private var listDetent: PresentationDetent = .fraction(0.25)
    @State private var activeSheet: ActiveSheet?
    @State private var showOnboarding = false
    @State private var didEvaluateOnboarding = false

    private var theme: AppTheme {
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
                    showCloudOverlay: viewModel.showCloudOverlay,
                    isNightMode: viewModel.nightBannerText != nil,
                    warningMessage: viewModel.warningMessage,
                    onRegionChanged: { viewModel.mapRegionChanged($0) },
                    onSelectCafe: { cafe in
                        viewModel.selectCafeFromMap(cafe)
                        presentDetail(cafe)
                    },
                    onPermissionDenied: { viewModel.locationPermissionDenied() },
                    onUserLocationUpdate: { viewModel.updateUserLocation($0) }
                )
                .ignoresSafeArea()

                if mapHazeOpacity > 0 {
                    ThemeColor.coffeeDark
                        .opacity(mapHazeOpacity)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                topFloatingBar
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(.move(edge: .top).combined(with: .opacity))

                VStack(spacing: 8) {
                    statusPillsBar
                    statsHeader
                }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))

                mapFloatingControls
                    .padding(.trailing, 12)
                    .padding(.top, 96)
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
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await viewModel.onAppear()
            }
            .onAppear {
                guard !didEvaluateOnboarding else { return }
                didEvaluateOnboarding = true
                if !hasSeenOnboardingV1 {
                    showOnboarding = true
                }
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    viewModel.startAutoRefresh()
                default:
                    viewModel.stopAutoRefresh()
                }
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
                            presentDetail(cafe)
                        }
                    )
                    .presentationDetents([.fraction(0.25), .medium, .large], selection: $listDetent)
                    .presentationBackgroundInteraction(.enabled)
                    .presentationDragIndicator(.visible)
                    .presentationBackground(ThemeColor.surface)
                    .animation(.spring(response: 0.35, dampingFraction: 0.9), value: listDetent)
                case .filters:
                    FiltersSheetView(
                        viewModel: viewModel,
                        onReplayTutorial: {
                            activeSheet = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                showOnboarding = true
                            }
                        }
                    )
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                        .presentationBackground(ThemeColor.surface)
                case .favorites:
                    FavoritesView(
                        cafes: viewModel.favoriteCafes,
                        onTapCafe: { cafe in
                            viewModel.selectCafeFromList(cafe)
                            presentDetail(cafe)
                        },
                        onRemoveFavorite: { cafe in
                            viewModel.toggleFavorite(cafe)
                        }
                    )
                    .presentationDetents([.fraction(0.25), .medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(ThemeColor.surface)
                case .forecastTime:
                    ForecastTimeSheetView(viewModel: viewModel)
                        .presentationDetents([.fraction(0.55)])
                        .presentationDragIndicator(.visible)
                        .presentationBackground(.ultraThinMaterial)
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
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingView {
                    hasSeenOnboardingV1 = true
                    showOnboarding = false
                }
                .preferredColorScheme(theme.preferredColorScheme)
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

    private var topFloatingBar: some View {
        HStack {
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                ZStack {
                    Color.clear
                    Image("BrandCup")
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 44, height: 44)
                }
                .frame(width: 28, height: 28)
                Text("SunnySips")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(ThemeColor.coffeeDark)
                    .lineLimit(1)
                    .minimumScaleFactor(0.92)
                    .allowsTightening(true)

                Button {
                    presentFilters()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ThemeColor.coffeeDark)
                        .frame(width: 30, height: 30)
                        .background(ThemeColor.surfaceSoft.opacity(0.95), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Search cafes")
            }
            .padding(.horizontal, 18)
            .frame(height: 54)
            .background(ThemeColor.surface.opacity(0.98), in: Capsule())
            .overlay(Capsule().stroke(ThemeColor.line.opacity(0.55), lineWidth: 1))
            .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var statusPillsBar: some View {
        HStack(spacing: 8) {
            Label(skyCoveragePillText, systemImage: skyCoveragePillSymbol)
                .timePillStyle(skyCoveragePillTone, size: .small)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .truncationMode(.tail)
                .frame(minWidth: 116, alignment: .leading)

            Spacer(minLength: 8)

            Label(weatherStatusPillText, systemImage: weatherStatusPillSymbol)
                .timePillStyle(.muted, size: .small)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .truncationMode(.tail)
                .frame(minWidth: 116, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
    }

    private var statsHeader: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
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
                        HStack(spacing: 4) {
                            Text(viewModel.areaTitle)
                                .font(.headline.weight(.semibold))
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.bold))
                        }
                        .foregroundStyle(ThemeColor.ink)
                    }

                    Text("\(viewModel.cafes.count) cafes")
                        .font(.caption2)
                        .foregroundStyle(ThemeColor.muted)
                }

                Spacer(minLength: 6)

                Picker("", selection: useNowBinding) {
                    Text("Live").tag(true)
                    Text("Forecast").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 154)

                headerIconButton(systemName: "line.3.horizontal", accessibility: "Open filters") {
                    presentFilters()
                }
            }

            HStack(spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: cloudPercentRounded >= 60 ? "cloud.fill" : "cloud.sun.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ThemeColor.focusBlue)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cloud \(cloudPercentRounded)%")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ThemeColor.ink)

                        ProgressView(value: Double(cloudPercentRounded), total: 100.0)
                            .tint(ThemeColor.accentGold)
                            .accessibilityLabel("Cloud cover \(cloudPercentRounded) percent")
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 54)
                .background(ThemeColor.surfaceSoft.opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .trailing, spacing: 2) {
                    Button {
                        Task { await viewModel.refreshTapped() }
                    } label: {
                        if viewModel.isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(ThemeColor.focusBlue)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Refresh cafes")

                    Text(viewModel.snapshotFreshnessText)
                        .font(.caption2)
                        .foregroundStyle(ThemeColor.muted)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 8) {
                bucketChip(bucket: .sunny, label: "\(viewModel.stats.sunny)", icon: "sun.max.fill", color: ThemeColor.sunnyGreen)
                bucketChip(bucket: .partial, label: "\(viewModel.stats.partial)", icon: "cloud.sun.fill", color: ThemeColor.partialAmber)
                bucketChip(bucket: .shaded, label: "\(viewModel.stats.shaded)", icon: "cloud.fill", color: ThemeColor.shadedRed)
                Spacer(minLength: 0)
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
                .padding(.vertical, 5)
                .background(ThemeColor.surfaceSoft.opacity(0.92), in: Capsule())
            }

            if !viewModel.filters.useNow {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Forecast")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(ThemeColor.muted)
                            Text(viewModel.selectedForecastTimeText)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(ThemeColor.ink)
                        }
                        Spacer(minLength: 8)
                        Button {
                            viewModel.useNowChanged(true)
                        } label: {
                            Label("Live", systemImage: "dot.radiowaves.left.and.right")
                                .timePillStyle(.secondary, size: .small)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Back to live mode")
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            forecastJumpChip(minutes: 30)
                            forecastJumpChip(minutes: 60)
                            forecastJumpChip(minutes: 120)
                            forecastJumpChip(minutes: 180)
                            forecastJumpChip(minutes: 360)
                            forecastJumpChip(minutes: 720)
                        }
                    }

                    Button {
                        presentForecastTimePicker()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar.badge.clock")
                            Text("Open Full Forecast Timeline")
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(ThemeColor.focusBlue)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(ThemeColor.focusBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open full forecast timeline")
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.filters.useNow)
        .padding(10)
        .background(
            LinearGradient(
                colors: [
                    ThemeColor.surface.opacity(0.98),
                    ThemeColor.surfaceSoft.opacity(0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(ThemeColor.line.opacity(0.55), lineWidth: 1)
        )
        .shadow(color: ThemeColor.coffeeDark.opacity(0.1), radius: 8, x: 0, y: 4)
    }

    private var useNowBinding: Binding<Bool> {
        Binding(
            get: { viewModel.filters.useNow },
            set: { useNow in
                viewModel.useNowChanged(useNow)
            }
        )
    }

    private var mapFloatingControls: some View {
        VStack(spacing: 10) {
            mapControlButton(systemName: "heart", accessibility: "Open favorites") {
                presentFavorites()
            }

            mapControlButton(systemName: "list.bullet", accessibility: "Open cafe list") {
                presentList()
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

            mapThemeMenuButton
        }
    }

    private func mapControlButton(systemName: String, accessibility: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ThemeColor.coffeeDark)
                .frame(width: 38, height: 38)
                .background(ThemeColor.surface.opacity(0.95), in: Circle())
                .overlay(Circle().stroke(ThemeColor.line.opacity(0.55), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
    }

    private var mapThemeMenuButton: some View {
        Menu {
            ForEach(AppTheme.allCases) { themeOption in
                Button {
                    themeRawValue = themeOption.rawValue
                } label: {
                    Label(themeOption.title, systemImage: themeOption.rawValue == themeRawValue ? "checkmark" : "circle")
                }
            }
        } label: {
            Image(systemName: "paintpalette")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ThemeColor.coffeeDark)
                .frame(width: 38, height: 38)
                .background(ThemeColor.surface.opacity(0.95), in: Circle())
                .overlay(Circle().stroke(ThemeColor.line.opacity(0.55), lineWidth: 1))
        }
        .accessibilityLabel("Choose app appearance")
    }

    private func headerIconButton(systemName: String, accessibility: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
        .modifier(HeaderIconChrome())
    }

    private func forecastJumpChip(minutes: Int) -> some View {
        let enabled = viewModel.canJumpForward(minutes: minutes)
        let selected = abs(selectedForecastOffsetMinutes - minutes) <= 15

        return Button {
            withAnimation(.spring(duration: 0.22)) {
                let target = Date().addingTimeInterval(Double(minutes) * 60.0)
                viewModel.setForecastTime(target)
            }
        } label: {
            Text(jumpLabel(minutes: minutes))
                .font(.caption.weight(.semibold))
                .foregroundStyle(selected ? ThemeColor.surface : ThemeColor.focusBlue)
                .padding(.horizontal, 11)
                .frame(height: 30)
                .background(
                    Capsule()
                        .fill(selected ? ThemeColor.focusBlue : ThemeColor.focusBlue.opacity(0.12))
                )
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel("Jump forward \(minutes >= 60 ? "\(minutes / 60) hours" : "\(minutes) minutes")")
    }

    private func jumpLabel(minutes: Int) -> String {
        if minutes < 60 { return "+\(minutes)m" }
        return "+\(minutes / 60)h"
    }

    private var selectedForecastOffsetMinutes: Int {
        guard !viewModel.filters.useNow else { return 0 }
        let now = Date().roundedDownToQuarterHour()
        return max(0, Int(viewModel.filters.selectedTime.timeIntervalSince(now) / 60.0))
    }

    private var cloudPercentRounded: Int {
        max(0, min(100, Int(viewModel.cloudCoverPct.rounded())))
    }

    private var sunnyPercentRounded: Int {
        max(0, min(100, 100 - cloudPercentRounded))
    }

    private var isNightStatus: Bool {
        viewModel.nightBannerText != nil
    }

    private var mapHazeOpacity: Double {
        if isNightStatus { return 0.3 }
        if viewModel.warningMessage != nil { return 0.22 }
        if viewModel.showCloudOverlay {
            return max(0.14, min((viewModel.cloudCoverPct / 100.0) * 0.44, 0.33))
        }
        return 0
    }

    private var skyCoveragePillText: String {
        if isNightStatus {
            return "Night"
        }
        if sunnyPercentRounded >= cloudPercentRounded {
            return "Sunny \(sunnyPercentRounded)%"
        }
        return "Cloud \(cloudPercentRounded)%"
    }

    private var skyCoveragePillSymbol: String {
        if isNightStatus { return "moon.stars.fill" }
        return sunnyPercentRounded >= cloudPercentRounded ? "sun.max.fill" : "cloud.fill"
    }

    private var skyCoveragePillTone: TimePillTone {
        if isNightStatus { return .secondary }
        return sunnyPercentRounded >= cloudPercentRounded ? .sunny : .secondary
    }

    private var weatherStatusPillText: String {
        if viewModel.usingLiveWeather {
            return viewModel.weatherIsForecast ? "Forecast" : "Live data"
        }
        return "Cached"
    }

    private var weatherStatusPillSymbol: String {
        viewModel.weatherPillSymbol
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
                    .foregroundStyle(isSelected ? ThemeColor.surface : ThemeColor.coffeeDark)
            }
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? color.opacity(0.95) : ThemeColor.surfaceSoft.opacity(0.95))
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
                showCloudOverlay: viewModel.showCloudOverlay,
                isNightMode: viewModel.nightBannerText != nil,
                warningMessage: viewModel.warningMessage,
                onRegionChanged: { viewModel.mapRegionChanged($0) },
                onSelectCafe: { cafe in
                    viewModel.selectCafeFromMap(cafe)
                    presentDetail(cafe)
                },
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

    private func presentForecastTimePicker() {
        viewModel.selectedCafe = nil
        activeSheet = .forecastTime
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

    private func presentDetail(_ cafe: SunnyCafe) {
        activeSheet = .detail(cafe)
    }

}

private struct HeaderIconChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(ThemeColor.coffeeDark)
            .frame(width: 32, height: 32)
            .background(ThemeColor.surface.opacity(0.95), in: Circle())
            .overlay(Circle().stroke(ThemeColor.line.opacity(0.55), lineWidth: 1))
    }
}
