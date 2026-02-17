import Foundation

enum BucketFilter: String, CaseIterable, Identifiable {
    case all
    case sunny
    case partial
    case shaded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .sunny: return "Sunny"
        case .partial: return "Partial"
        case .shaded: return "Shaded"
        }
    }

    func matches(_ cafe: CafeSnapshot) -> Bool {
        if self == .all {
            return true
        }
        return cafe.resolvedBucket == rawValue
    }
}

enum SortOrder: String, CaseIterable, Identifiable {
    case score
    case name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .score: return "Best Score"
        case .name: return "Name"
        }
    }
}

@MainActor
final class SunnySipsViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var snapshotIndex: SnapshotIndex?
    @Published var areaSnapshot: AreaSnapshotFile?

    @Published var selectedArea: String = AppConfig.defaultArea
    @Published var selectedTimeUTC: String?
    @Published var selectedBucket: BucketFilter = .all
    @Published var minScore: Double = 0
    @Published var searchText = ""
    @Published var hideShaded = false
    @Published var sortOrder: SortOrder = .score
    @Published var selectedCafe: CafeSnapshot?

    private let service = SnapshotService()
    private var hasLoaded = false

    var availableAreas: [SnapshotAreaRef] {
        (snapshotIndex?.areas ?? []).sorted { $0.area < $1.area }
    }

    var availableTimeSnapshots: [TimeSnapshot] {
        areaSnapshot?.snapshots ?? []
    }

    var activeTimeSnapshot: TimeSnapshot? {
        let snapshots = availableTimeSnapshots
        guard !snapshots.isEmpty else { return nil }
        if let selectedTimeUTC,
           let matched = snapshots.first(where: { $0.timeUTC == selectedTimeUTC }) {
            return matched
        }
        return snapshots.first
    }

    var filteredCafes: [CafeSnapshot] {
        guard let cafes = activeTimeSnapshot?.cafes else { return [] }
        let filtered = cafes
            .filter { selectedBucket.matches($0) }
            .filter { !hideShaded || $0.resolvedBucket != "shaded" }
            .filter { $0.sunnyScore >= minScore }
            .filter { cafe in
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                if query.isEmpty { return true }
                return cafe.name.localizedCaseInsensitiveContains(query)
            }
        switch sortOrder {
        case .score:
            return filtered.sorted { lhs, rhs in
                if lhs.sunnyScore != rhs.sunnyScore {
                    return lhs.sunnyScore > rhs.sunnyScore
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        case .name:
            return filtered.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    var lastUpdatedText: String? {
        guard let raw = areaSnapshot?.generatedAtUTC else { return nil }
        guard let date = Self.parseISO(raw) else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let relative = formatter.localizedString(for: date, relativeTo: Date())
        return "Updated \(relative)"
    }

    func displayName(for area: String) -> String {
        switch area {
        case "core-cph": return "Core Copenhagen"
        case "indre-by": return "Indre By"
        case "norrebro": return "Norrebro"
        case "frederiksberg": return "Frederiksberg"
        case "osterbro": return "Osterbro"
        default:
            return area
                .replacingOccurrences(of: "-", with: " ")
                .capitalized
        }
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await refresh()
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        do {
            let index = try await service.fetchIndex(baseURL: AppConfig.snapshotBaseURL)
            snapshotIndex = index

            if !index.areas.contains(where: { $0.area == selectedArea }),
               let firstArea = index.areas.first?.area {
                selectedArea = firstArea
            }
            try await loadAreaSnapshot(for: selectedArea)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadAreaSnapshot(for area: String) async throws {
        guard let areaRef = snapshotIndex?.areas.first(where: { $0.area == area }) else {
            areaSnapshot = nil
            selectedTimeUTC = nil
            return
        }
        let snapshot = try await service.fetchAreaSnapshot(
            fileName: areaRef.file,
            baseURL: AppConfig.snapshotBaseURL
        )
        areaSnapshot = snapshot
        selectedTimeUTC = snapshot.snapshots.first?.timeUTC
        selectedCafe = nil
    }

    func didSelectArea(_ area: String) {
        Task {
            do {
                try await loadAreaSnapshot(for: area)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func selectNow() {
        selectedTimeUTC = availableTimeSnapshots.first?.timeUTC
    }

    func resetFilters() {
        selectedBucket = .all
        minScore = 0
        searchText = ""
        hideShaded = false
        sortOrder = .score
    }

    private static func parseISO(_ value: String) -> Date? {
        if let d = ISO8601DateFormatter.withFractionalSeconds.date(from: value) {
            return d
        }
        return ISO8601DateFormatter.internetDateTime.date(from: value)
    }
}
