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
        return cafes
            .filter { selectedBucket.matches($0) }
            .filter { $0.sunnyScore >= minScore }
            .filter { cafe in
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                if query.isEmpty { return true }
                return cafe.name.localizedCaseInsensitiveContains(query)
            }
            .sorted { lhs, rhs in
                if lhs.sunnyScore != rhs.sunnyScore {
                    return lhs.sunnyScore > rhs.sunnyScore
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
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
}
