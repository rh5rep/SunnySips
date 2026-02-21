import Foundation
import MapKit
import UIKit
import SwiftUI
import CoreLocation

@MainActor
final class SunnySipsViewModel: ObservableObject {
    @Published private(set) var cafes: [SunnyCafe] = []
    @Published private(set) var visibleCafes: [SunnyCafe] = []
    @Published private(set) var stats: SunnyStatsSummary = .empty
    @Published private(set) var cloudCoverPct: Double = 0
    @Published private(set) var updatedAt: Date?
    @Published private(set) var sunModelTime: Date?
    @Published private(set) var sunModelInterpolated = false
    @Published private(set) var weatherUpdatedAt: Date?
    @Published private(set) var weatherTargetAt: Date?
    @Published private(set) var weatherSource = "Snapshot"
    @Published private(set) var usingLiveWeather = false
    @Published private(set) var weatherFallbackMessage: String?
    @Published private(set) var usingCachedData = false
    @Published private(set) var weatherIsForecast = false
    @Published private(set) var isFuturePrediction = false

    @Published private(set) var userLocation: CLLocationCoordinate2D?
    @Published private(set) var favoriteCafeIDs: Set<String> = []

    @Published var selectedCafe: SunnyCafe?
    @Published var mapRegion: MKCoordinateRegion = SunnyArea.coreCopenhagen.bbox.region
    @Published var visibleRegion: MKCoordinateRegion = SunnyArea.coreCopenhagen.bbox.region

    @Published var filters = SunnyFilters()

    @Published var isInitialLoading = true
    @Published var isRefreshing = false
    @Published var isFullMapPresented = false
    @Published var showLocationSettingsPrompt = false
    @Published var errorMessage: String?
    @Published var warningMessage: String?
    @Published var use3DMap = false

    @Published var locateUserRequestID = 0

    private let apiService = SunnyAPIService()
    private let liveWeatherService = LiveWeatherService()
    private var allCafes: [SunnyCafe] = []
    private var hasLoaded = false
    private var searchTask: Task<Void, Never>?
    private var autoRefreshTask: Task<Void, Never>?

    private let favoritesDefaultsKey = "sunnysips.favoriteCafeIDs"
    private let copenhagenTimeZone = TimeZone(identifier: "Europe/Copenhagen") ?? .current

    var areaTitle: String { filters.area.title }
    var quickJumpMinutes: [Int] { [30, 60, 120, 180, 360] }

    var showCloudOverlay: Bool {
        cloudCoverPct >= 50.0 || warningMessage != nil || !isDaylight(at: selectedTargetTime)
    }

    var predictionRange: ClosedRange<Date> {
        predictionRangeForCurrentArea()
    }

    var selectedForecastTimeText: String {
        let formatter = DateFormatter()
        formatter.calendar = Date.copenhagenCalendar
        formatter.timeZone = copenhagenTimeZone
        formatter.dateFormat = "EEE HH:mm"
        return formatter.string(from: selectedTargetTime)
    }

    var selectedForecastShortTimeText: String {
        let formatter = DateFormatter()
        formatter.calendar = Date.copenhagenCalendar
        formatter.timeZone = copenhagenTimeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: selectedTargetTime)
    }

    var nightBannerText: String? {
        isDaylight(at: selectedTargetTime) ? nil : "Nighttime - no sun possible at selected time"
    }

    var mapBannerText: String? {
        if !isDaylight(at: selectedTargetTime) {
            return "Night in Copenhagen - no direct sun"
        }
        if cloudCoverPct >= 95 {
            return "Overcast \(Int(cloudCoverPct.rounded()))% - limited direct sun"
        }
        if let warningMessage {
            return warningMessage
        }
        return nil
    }

    var mapBannerSymbol: String {
        if !isDaylight(at: selectedTargetTime) { return "moon.stars.fill" }
        if cloudCoverPct >= 95 { return "cloud.fill" }
        return "exclamationmark.triangle.fill"
    }

    var mapBannerTone: TimePillTone {
        !isDaylight(at: selectedTargetTime) ? .secondary : .muted
    }

    var subtitleLine: String {
        let count = cafes.count
        let relative = updatedRelativeText
        return "\(count) cafes • \(relative)"
    }

    var updatedRelativeText: String {
        guard let updatedAt else { return "Not updated" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "Updated \(formatter.localizedString(for: updatedAt, relativeTo: Date()))"
    }

    var snapshotFreshnessText: String {
        guard let updatedAt else { return "Snapshot unknown" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let relative = formatter.localizedString(for: updatedAt, relativeTo: Date())
        return "Snapshot \(relative)"
    }

    var sunModelBadgeText: String {
        let base = "Sun model \(timeLabel(from: sunModelTime))"
        var tags: [String] = []
        if sunModelInterpolated { tags.append("interp") }
        if isFuturePrediction { tags.append("forecast") }
        if tags.isEmpty { return base }
        return "\(base) (\(tags.joined(separator: ", ")))"
    }

    var weatherBadgeText: String {
        if usingLiveWeather {
            let mode = weatherIsForecast ? "forecast" : "live"
            if weatherIsForecast {
                return "\(weatherSource) \(mode) for \(timeLabel(from: weatherTargetAt))"
            }
            return "\(weatherSource) \(mode) \(timeLabel(from: weatherUpdatedAt))"
        }
        if let weatherFallbackMessage {
            return weatherFallbackMessage
        }
        return "Weather snapshot"
    }

    var weatherFreshnessText: String {
        if usingLiveWeather {
            if weatherIsForecast {
                return "Forecast for \(timeLabel(from: weatherTargetAt))"
            }
            return "Weather live \(timeLabel(from: weatherUpdatedAt))"
        }
        if weatherFallbackMessage != nil {
            return "Weather snapshot fallback"
        }
        return "Weather snapshot"
    }

    var weatherPillText: String {
        if usingLiveWeather {
            if weatherIsForecast {
                return "Forecast data"
            }
            return "Live data"
        }
        return "Cached data"
    }

    var weatherPillSymbol: String {
        if usingLiveWeather {
            return weatherIsForecast ? "clock.badge.checkmark" : "dot.radiowaves.left.and.right"
        }
        return "archivebox.fill"
    }

    var blockingError: String? {
        guard allCafes.isEmpty else { return nil }
        return errorMessage
    }

    var favoriteCafes: [SunnyCafe] {
        allCafes
            .filter { favoriteCafeIDs.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func jumpForward(minutes: Int) {
        let base = filters.useNow ? Date().roundedDownToQuarterHour() : filters.selectedTime
        let rawTarget = base.addingTimeInterval(Double(minutes) * 60.0)
        let clampedTarget = clampToPredictionRange(rawTarget)
        guard clampedTarget != base else { return }

        filters.useNow = false
        timeChanged(clampedTarget)
    }

    func setForecastTime(_ date: Date) {
        filters.useNow = false
        timeChanged(date)
    }

    func canJumpForward(minutes: Int) -> Bool {
        let base = filters.useNow ? Date().roundedDownToQuarterHour() : filters.selectedTime
        let rawTarget = base.addingTimeInterval(Double(minutes) * 60.0)
        let clampedTarget = clampToPredictionRange(rawTarget)
        return clampedTarget > base
    }

    func onAppear() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        loadFavoritesFromDefaults()
        mapRegion = filters.area.bbox.region
        visibleRegion = mapRegion
        await reloadFromAPI()
        startAutoRefresh()
    }

    func startAutoRefresh(every seconds: TimeInterval = 300) {
        guard autoRefreshTask == nil else { return }
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                let ns = UInt64(max(seconds, 60) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
                guard let self, !Task.isCancelled else { break }
                await self.reloadFromAPI(silent: true)
            }
        }
    }

    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    func refreshTapped() async {
        await reloadFromAPI()
    }

    func resetFilters() {
        filters.selectedBuckets = [.sunny]
        filters.minScore = 0
        filters.searchText = ""
        filters.sort = .bestScore
        filters.favoritesOnly = false
        applyLocalFilters()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func areaChanged(_ area: SunnyArea) {
        filters.area = area
        withAnimation(.spring(duration: 0.35)) {
            mapRegion = area.bbox.region
        }
        Task { await reloadFromAPI() }
    }

    func useNowChanged(_ useNow: Bool) {
        filters.useNow = useNow
        if useNow {
            // Reset forecast baseline so returning to forecast starts fresh.
            filters.selectedTime = clampToPredictionRange(Date().addingTimeInterval(30 * 60))
        } else {
            filters.selectedTime = clampToPredictionRange(filters.selectedTime)
        }
        Task { await reloadFromAPI() }
    }

    func resetForecastTime() {
        filters.selectedTime = clampToPredictionRange(Date().addingTimeInterval(30 * 60))
        guard !filters.useNow else { return }
        Task { await reloadFromAPI() }
    }

    func togglePredictFutureMode() {
        if filters.useNow {
            filters.useNow = false
            filters.selectedTime = clampToPredictionRange(Date().addingTimeInterval(30 * 60))
        } else {
            filters.useNow = true
        }
        Task { await reloadFromAPI() }
    }

    func timeChanged(_ date: Date) {
        let rounded = clampToPredictionRange(date)
        if rounded != filters.selectedTime {
            filters.selectedTime = rounded
        }
        guard !filters.useNow else { return }
        Task { await reloadFromAPI() }
    }

    func toggleBucket(_ bucket: SunnyBucketFilter) {
        if filters.selectedBuckets.contains(bucket) {
            filters.selectedBuckets.remove(bucket)
        } else {
            filters.selectedBuckets.insert(bucket)
        }
        applyLocalFilters()
    }

    func favoritesOnlyChanged(_ value: Bool) {
        filters.favoritesOnly = value
        applyLocalFilters()
    }

    func minScoreChanged(_ value: Double) {
        filters.minScore = value
        applyLocalFilters()
    }

    func sortChanged(_ sort: SunnySortOption) {
        filters.sort = sort
        applyLocalFilters()
    }

    func searchChanged(_ text: String) {
        filters.searchText = text
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard let self, !Task.isCancelled else { return }
            self.applyLocalFilters()
        }
    }

    func mapRegionChanged(_ region: MKCoordinateRegion) {
        visibleRegion = region
        visibleCafes = cafes.filter { region.contains($0.coordinate) }
    }

    func selectCafeFromList(_ cafe: SunnyCafe) {
        withAnimation(.spring(duration: 0.35)) {
            mapRegion = MKCoordinateRegion(
                center: cafe.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
            )
        }
        selectedCafe = cafe
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func selectCafeFromMap(_ cafe: SunnyCafe) {
        selectedCafe = cafe
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    func requestLocateUser() {
        locateUserRequestID += 1
    }

    func locationPermissionDenied() {
        showLocationSettingsPrompt = true
    }

    func updateUserLocation(_ coordinate: CLLocationCoordinate2D) {
        userLocation = coordinate
        if filters.sort == .distanceFromUser {
            applyLocalFilters()
        }
    }

    func toggleFavorite(_ cafe: SunnyCafe) {
        if favoriteCafeIDs.contains(cafe.id) {
            favoriteCafeIDs.remove(cafe.id)
        } else {
            favoriteCafeIDs.insert(cafe.id)
        }
        persistFavoritesToDefaults()
        applyLocalFilters()
    }

    func isFavorite(_ cafe: SunnyCafe) -> Bool {
        favoriteCafeIDs.contains(cafe.id)
    }

    func toggleMapStyle() {
        use3DMap.toggle()
    }

    func applyQuickPreset(_ preset: SunnyQuickPreset) {
        switch preset {
        case .bestRightNow:
            filters.useNow = true
            filters.selectedBuckets = [.sunny]
            filters.favoritesOnly = false
            filters.sort = .bestScore
            filters.minScore = 20
        case .sunnyAfternoon:
            filters.useNow = false
            let afternoon = Date.copenhagenCalendar.date(
                bySettingHour: 15,
                minute: 0,
                second: 0,
                of: Date()
            ) ?? Date().addingTimeInterval(2 * 3600)
            filters.selectedTime = clampToPredictionRange(afternoon)
            filters.selectedBuckets = [.sunny, .partial]
            filters.favoritesOnly = false
            filters.sort = .mostSunny
            filters.minScore = 10
        case .favoritesNearMe:
            filters.useNow = true
            filters.selectedBuckets = [.sunny, .partial, .shaded]
            filters.favoritesOnly = true
            filters.sort = .distanceFromUser
            filters.minScore = 0
        }
        applyLocalFilters()
        Task { await reloadFromAPI() }
    }

    private func reloadFromAPI(silent: Bool = false) async {
        if silent {
            isRefreshing = true
        } else {
            isInitialLoading = allCafes.isEmpty
            isRefreshing = !isInitialLoading
        }
        errorMessage = nil

        do {
            let selectedTargetTime = filters.useNow ? Date() : clampToPredictionRange(filters.selectedTime)
            let requestedTimeForBackend = filters.useNow ? nil : selectedTargetTime
            isFuturePrediction = selectedTargetTime > Date().addingTimeInterval(15 * 60)

            let result = try await apiService.fetchSunny(area: filters.area, requestedTime: requestedTimeForBackend)
            usingCachedData = result.fromCache
            updatedAt = result.fetchedAt
            sunModelTime = result.response.time
            sunModelInterpolated = result.sunModelInterpolated
            var effectiveCloudCover = result.response.cloudCoverPct
            var effectiveCafes = result.response.cafes
            usingLiveWeather = false
            weatherUpdatedAt = nil
            weatherTargetAt = nil
            weatherFallbackMessage = nil
            weatherSource = "Snapshot"
            weatherIsForecast = isFuturePrediction

            if let liveWeather = try? await liveWeatherService.fetchCloudCover(
                area: filters.area,
                at: selectedTargetTime
            ) {
                effectiveCloudCover = liveWeather.cloudCoverPct
                effectiveCafes = result.response.cafes.map { $0.applyingCloudCover(liveWeather.cloudCoverPct) }
                usingLiveWeather = true
                weatherUpdatedAt = liveWeather.fetchedAt
                weatherTargetAt = liveWeather.targetTime
                weatherSource = liveWeather.source
                weatherIsForecast = liveWeather.isForecast
#if DEBUG
                print("SunnySips weather live source=\(liveWeather.source) cloud=\(Int(liveWeather.cloudCoverPct)) target=\(liveWeather.targetTime) interpolated=\(liveWeather.interpolated)")
#endif
            } else {
                weatherFallbackMessage = "Weather unavailable - using snapshot"
#if DEBUG
                print("SunnySips weather fallback: using snapshot cloud=\(Int(effectiveCloudCover))")
#endif
            }

            cloudCoverPct = effectiveCloudCover
            if !isDaylight(at: selectedTargetTime) {
                effectiveCafes = effectiveCafes.map { $0.applyingNightOverride() }
            }
            allCafes = effectiveCafes
            warningMessage = nil

            if result.fromCache {
                errorMessage = "Offline mode: showing cached cafes."
            }

            applyLocalFilters()
        } catch {
            if allCafes.isEmpty {
                errorMessage = error.localizedDescription
            } else {
                errorMessage = "Could not refresh right now. Showing previous data."
            }
        }

        isInitialLoading = false
        isRefreshing = false
    }

    private func applyLocalFilters() {
        let search = filters.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedBuckets = filters.selectedBuckets
        var filtered = allCafes
            .filter {
                // While searching, include all buckets so matches are not hidden by sunny/partial/shaded toggles.
                if !search.isEmpty { return true }
                return selectedBuckets.isEmpty || selectedBuckets.contains(effectiveCondition(for: $0).filterValue)
            }
            .filter { $0.sunnyScore >= filters.minScore }
            .filter { !filters.favoritesOnly || favoriteCafeIDs.contains($0.id) }

        if !search.isEmpty {
            filtered = filtered.filter { $0.matchesFuzzy(search) }
        }

        switch filters.sort {
        case .bestScore:
            filtered.sort {
                if $0.sunnyScore != $1.sunnyScore {
                    return $0.sunnyScore > $1.sunnyScore
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .mostSunny:
            filtered.sort {
                let left = conditionRank(effectiveCondition(for: $0))
                let right = conditionRank(effectiveCondition(for: $1))
                if left != right {
                    return left > right
                }
                return $0.sunnyScore > $1.sunnyScore
            }
        case .nameAZ:
            filtered.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .distanceFromUser:
            filtered.sort {
                let reference = userLocation ?? filters.area.bbox.center
                let left = $0.distanceMeters(from: reference) ?? .greatestFiniteMagnitude
                let right = $1.distanceMeters(from: reference) ?? .greatestFiniteMagnitude
                if left != right {
                    return left < right
                }
                return $0.sunnyScore > $1.sunnyScore
            }
        case .popularity:
            filtered.sort {
                if $0.popularityScore != $1.popularityScore {
                    return $0.popularityScore > $1.popularityScore
                }
                return $0.sunnyScore > $1.sunnyScore
            }
        }

        cafes = filtered
        visibleCafes = cafes.filter { visibleRegion.contains($0.coordinate) }
        stats = summarize(allCafes)

        if let selectedCafe, !cafes.contains(selectedCafe) {
            self.selectedCafe = nil
        }
    }

    private func summarize(_ cafes: [SunnyCafe]) -> SunnyStatsSummary {
        guard !cafes.isEmpty else { return .empty }

        var sunny = 0
        var partial = 0
        var shaded = 0
        var scoreSum = 0.0

        for cafe in cafes {
            switch effectiveCondition(for: cafe) {
            case .sunny: sunny += 1
            case .partial: partial += 1
            case .shaded: shaded += 1
            }
            scoreSum += cafe.sunnyScore
        }

        return SunnyStatsSummary(
            total: cafes.count,
            sunny: sunny,
            partial: partial,
            shaded: shaded,
            averageScore: Int((scoreSum / Double(cafes.count)).rounded())
        )
    }

    private func timeLabel(from date: Date?) -> String {
        guard let date else { return "--:--" }
        let formatter = DateFormatter()
        formatter.calendar = Date.copenhagenCalendar
        formatter.timeZone = copenhagenTimeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func effectiveCondition(for cafe: SunnyCafe) -> EffectiveCondition {
        let time = selectedTargetTime
        guard isDaylight(at: time) else { return .shaded }
        let cloud = cafe.cloudCoverPct ?? cloudCoverPct
        return cafe.effectiveCondition(at: time, cloudCover: cloud)
    }

    private func conditionRank(_ condition: EffectiveCondition) -> Int {
        switch condition {
        case .sunny: return 2
        case .partial: return 1
        case .shaded: return 0
        }
    }

    private func loadFavoritesFromDefaults() {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: favoritesDefaultsKey),
              let ids = try? JSONDecoder().decode([String].self, from: data)
        else {
            favoriteCafeIDs = []
            return
        }
        favoriteCafeIDs = Set(ids)
    }

    private func persistFavoritesToDefaults() {
        let ids = Array(favoriteCafeIDs).sorted()
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(ids) {
            defaults.set(data, forKey: favoritesDefaultsKey)
        }
    }

    private var selectedTargetTime: Date {
        filters.useNow ? Date() : filters.selectedTime
    }

    private func clampToPredictionRange(_ date: Date) -> Date {
        let range = predictionRangeForCurrentArea(reference: Date())
        let rounded = date.roundedDownToQuarterHour()
        if rounded < range.lowerBound { return range.lowerBound.roundedDownToQuarterHour() }
        if rounded > range.upperBound { return range.upperBound.roundedDownToQuarterHour() }
        return rounded
    }

    private func predictionRangeForCurrentArea(reference: Date = Date()) -> ClosedRange<Date> {
        _ = reference
        return Date.predictionRange24h
    }

    private func isDaylight(at date: Date) -> Bool {
        if let window = SunlightCalculator.daylightWindow(
            on: date,
            coordinate: filters.area.bbox.center,
            timeZone: copenhagenTimeZone
        ) {
            return window.contains(date)
        }

        if let elevation = allCafes.first?.sunElevationDeg {
            return elevation > 0
        }
        return true
    }
}
