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
    @State private var showCafeSearchField = false
    @State private var cafeSearchText = ""
    @State private var isForecastPlaybackActive = false
    @State private var forecastPlaybackTask: Task<Void, Never>?
    @FocusState private var cafeSearchFocused: Bool

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

                if isCafeSearchListVisible {
                    cafeSearchResultsOverlay
                        .padding(.horizontal, 20)
                        .padding(.top, 74)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .zIndex(5)
                }

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
                cafeSearchText = viewModel.filters.searchText
                guard !didEvaluateOnboarding else { return }
                didEvaluateOnboarding = true
                if !hasSeenOnboardingV1 {
                    showOnboarding = true
                }
            }
            .onChange(of: cafeSearchText) { _, text in
                viewModel.searchChanged(text)
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    viewModel.startAutoRefresh()
                default:
                    viewModel.stopAutoRefresh()
                    stopForecastPlayback()
                }
            }
            .onChange(of: viewModel.filters.useNow) { _, isNow in
                if isNow {
                    stopForecastPlayback()
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
                if showCafeSearchField {
                    HStack(spacing: 6) {
                        TextField("Search cafes", text: $cafeSearchText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($cafeSearchFocused)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(ThemeColor.coffeeDark)

                        Button {
                            if cafeSearchText.isEmpty {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showCafeSearchField = false
                                }
                                cafeSearchFocused = false
                            } else {
                                cafeSearchText = ""
                            }
                        } label: {
                            Image(systemName: cafeSearchText.isEmpty ? "xmark" : "xmark.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(ThemeColor.coffeeDark.opacity(0.85))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(cafeSearchText.isEmpty ? "Close cafe search" : "Clear cafe search")
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(ThemeColor.surfaceSoft.opacity(0.92), in: Capsule())
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    Text("SunnySips")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(ThemeColor.coffeeDark)
                        .lineLimit(1)
                        .minimumScaleFactor(0.92)
                        .allowsTightening(true)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showCafeSearchField = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            cafeSearchFocused = true
                        }
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

    private var isCafeSearchListVisible: Bool {
        let query = cafeSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return showCafeSearchField && !query.isEmpty
    }

    private var cafeSearchResults: [SunnyCafe] {
        Array(viewModel.cafes.prefix(8))
    }

    private var cafeSearchResultsOverlay: some View {
        VStack(alignment: .leading, spacing: 0) {
            if cafeSearchResults.isEmpty {
                Text("No cafes found")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ThemeColor.muted)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            } else {
                ForEach(cafeSearchResults) { cafe in
                    Button {
                        viewModel.selectCafeFromList(cafe)
                        presentDetail(cafe)
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showCafeSearchField = false
                        }
                        cafeSearchFocused = false
                    } label: {
                        HStack(spacing: 8) {
                            let condition = cafe.effectiveCondition(at: Date(), cloudCover: cafe.cloudCoverPct ?? viewModel.cloudCoverPct)
                            Circle()
                                .fill(condition.color)
                                .frame(width: 9, height: 9)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(cafe.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ThemeColor.ink)
                                    .lineLimit(1)
                                Text("\(condition.rawValue) • \(cafe.scoreString)")
                                    .font(.caption)
                                    .foregroundStyle(ThemeColor.muted)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(ThemeColor.muted.opacity(0.8))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)

                    if cafe.id != cafeSearchResults.last?.id {
                        Divider()
                            .overlay(ThemeColor.line.opacity(0.35))
                            .padding(.horizontal, 12)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ThemeColor.surface.opacity(0.98), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(ThemeColor.line.opacity(0.55), lineWidth: 1)
        )
        .shadow(color: ThemeColor.coffeeDark.opacity(0.12), radius: 8, x: 0, y: 4)
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
                Spacer(minLength: 8)
                modeToggleBar
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
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.resetForecastTime()
                            }
                        } label: {
                            Label("Reset", systemImage: "arrow.counterclockwise")
                                .timePillStyle(.secondary, size: .small)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Reset forecast time")

                        Button {
                            toggleForecastPlayback()
                        } label: {
                            Label(
                                isForecastPlaybackActive ? "Pause" : "Play +3h",
                                systemImage: isForecastPlaybackActive ? "pause.fill" : "play.fill"
                            )
                            .timePillStyle(isForecastPlaybackActive ? .primary : .secondary, size: .small)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isForecastPlaybackActive ? "Pause forecast playback" : "Play forecast 3 hours ahead")
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            forecastJumpChip(minutes: 15)
                            forecastJumpChip(minutes: 30)
                            forecastJumpChip(minutes: 60)
                            forecastJumpChip(minutes: 120)
                            forecastJumpChip(minutes: 180)
                            forecastJumpChip(minutes: 360)
                        }
                    }

                    if isForecastPlaybackActive {
                        Text("Playing forecast in 30 minute steps to +3h")
                            .font(.caption2)
                            .foregroundStyle(ThemeColor.muted)
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

    private var modeToggleBar: some View {
        HStack(spacing: 4) {
            modeToggleButton(title: "Live", useNow: true)
            modeToggleButton(title: "Forecast", useNow: false)
        }
        .padding(4)
        .background(ThemeColor.surfaceSoft.opacity(0.98), in: Capsule())
        .overlay(Capsule().stroke(ThemeColor.line.opacity(0.4), lineWidth: 1))
        .fixedSize(horizontal: true, vertical: false)
    }

    private func modeToggleButton(title: String, useNow: Bool) -> some View {
        let isSelected = viewModel.filters.useNow == useNow
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.useNowChanged(useNow)
            }
        } label: {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isSelected ? ThemeColor.surface : ThemeColor.coffeeDark)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(
                    Capsule()
                        .fill(isSelected ? ThemeColor.focusBlue : .clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Switch to \(title) mode")
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
        let selected = selectedForecastChipMinutes == minutes

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

    private var selectedForecastChipMinutes: Int {
        let options = [15, 30, 60, 120, 180, 360]
        let offset = selectedForecastOffsetMinutes
        return options.min {
            let left = abs($0 - offset)
            let right = abs($1 - offset)
            if left == right { return $0 < $1 }
            return left < right
        } ?? 15
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

    private func toggleForecastPlayback() {
        if isForecastPlaybackActive {
            stopForecastPlayback()
        } else {
            startForecastPlayback()
        }
    }

    private func startForecastPlayback() {
        stopForecastPlayback()
        if viewModel.filters.useNow {
            viewModel.useNowChanged(false)
        }
        isForecastPlaybackActive = true

        let base = Date().roundedDownToQuarterHour()
        let start = max(base, viewModel.predictionRange.lowerBound.roundedDownToQuarterHour())
        let maxEnd = viewModel.predictionRange.upperBound.roundedDownToQuarterHour()
        let end = min(start.addingTimeInterval(3 * 60 * 60), maxEnd)
        let step: TimeInterval = 30 * 60

        forecastPlaybackTask = Task { @MainActor in
            var current = start
            viewModel.setForecastTime(current)

            while !Task.isCancelled && current < end {
                try? await Task.sleep(nanoseconds: 1_050_000_000)
                guard !Task.isCancelled else { break }
                current = min(current.addingTimeInterval(step), end)
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.setForecastTime(current)
                }
            }

            isForecastPlaybackActive = false
            forecastPlaybackTask = nil
        }
    }

    private func stopForecastPlayback() {
        forecastPlaybackTask?.cancel()
        forecastPlaybackTask = nil
        isForecastPlaybackActive = false
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
