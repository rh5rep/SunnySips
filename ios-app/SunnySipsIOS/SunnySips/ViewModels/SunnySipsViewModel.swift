import Foundation
import MapKit
import UIKit
import SwiftUI

@MainActor
final class SunnySipsViewModel: ObservableObject {
    @Published private(set) var cafes: [SunnyCafe] = []
    @Published private(set) var visibleCafes: [SunnyCafe] = []
    @Published private(set) var stats: SunnyStatsSummary = .empty
    @Published private(set) var cloudCoverPct: Double = 0
    @Published private(set) var updatedAt: Date?
    @Published private(set) var usingCachedData = false

    @Published var selectedCafe: SunnyCafe?
    @Published var mapRegion: MKCoordinateRegion = SunnyArea.coreCopenhagen.bbox.region
    @Published var visibleRegion: MKCoordinateRegion = SunnyArea.coreCopenhagen.bbox.region

    @Published var filters = SunnyFilters()

    @Published var isInitialLoading = true
    @Published var isRefreshing = false
    @Published var isFullMapPresented = false
    @Published var showLocationSettingsPrompt = false
    @Published var errorMessage: String?

    @Published var locateUserRequestID = 0

    private let apiService = SunnyAPIService()
    private var allCafes: [SunnyCafe] = []
    private var hasLoaded = false
    private var searchTask: Task<Void, Never>?
    private var autoRefreshTask: Task<Void, Never>?

    var areaTitle: String { filters.area.title }

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

    var blockingError: String? {
        guard allCafes.isEmpty else { return nil }
        return errorMessage
    }

    func onAppear() async {
        guard !hasLoaded else { return }
        hasLoaded = true
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
            Task { await reloadFromAPI() }
        } else {
            filters.selectedTime = filters.selectedTime.clampedToToday().roundedToQuarterHour()
            Task { await reloadFromAPI() }
        }
    }

    func timeChanged(_ date: Date) {
        let rounded = date.clampedToToday().roundedToQuarterHour()
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
            try? await Task.sleep(nanoseconds: 300_000_000)
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

    private func reloadFromAPI(silent: Bool = false) async {
        if silent {
            isRefreshing = true
        } else {
            isInitialLoading = allCafes.isEmpty
            isRefreshing = !isInitialLoading
        }
        errorMessage = nil

        do {
            let requestedTime = filters.useNow ? nil : filters.selectedTime
            let result = try await apiService.fetchSunny(area: filters.area, requestedTime: requestedTime)
            usingCachedData = result.fromCache
            updatedAt = result.fetchedAt
            cloudCoverPct = result.response.cloudCoverPct
            allCafes = result.response.cafes

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
            .filter { selectedBuckets.isEmpty || selectedBuckets.contains($0.bucket.filterValue) }
            .filter { $0.sunnyScore >= filters.minScore }

        if !search.isEmpty {
            filtered = filtered.filter { $0.name.localizedCaseInsensitiveContains(search) }
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
                if $0.sunnyFraction != $1.sunnyFraction {
                    return $0.sunnyFraction > $1.sunnyFraction
                }
                return $0.sunnyScore > $1.sunnyScore
            }
        case .nameAZ:
            filtered.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
            switch cafe.bucket {
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
}
