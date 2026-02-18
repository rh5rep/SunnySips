import Foundation

enum SunnyAPIError: LocalizedError {
    case invalidURL
    case badResponse(Int)
    case noCachedData
    case decodeFailure
    case emptySnapshot

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL."
        case .badResponse(let code):
            return "Server returned HTTP \(code)."
        case .noCachedData:
            return "No cached cafes available offline."
        case .decodeFailure:
            return "Could not decode API response."
        case .emptySnapshot:
            return "Snapshot data is empty."
        }
    }
}

struct SunnyFetchResult {
    let response: SunnyResponse
    let fetchedAt: Date
    let fromCache: Bool
    let sunModelInterpolated: Bool
}

private struct CachedSunnyPayload: Codable {
    let fetchedAt: Date
    let response: SunnyResponse
}

private struct AreaSnapshotPayload: Codable {
    let generatedAtUTC: Date?
    let snapshots: [AreaSnapshot]

    enum CodingKeys: String, CodingKey {
        case generatedAtUTC = "generated_at_utc"
        case snapshots
    }
}

private struct AreaSnapshot: Codable {
    let timeUTC: Date
    let cloudCoverPct: Double
    let cafes: [SunnyCafe]

    enum CodingKeys: String, CodingKey {
        case timeUTC = "time_utc"
        case cloudCoverPct = "cloud_cover_pct"
        case cafes
    }
}

actor SunnyAPIService {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let fileManager: FileManager

    init(session: URLSession = .shared) {
        self.session = session
        self.fileManager = .default

        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let d = ISO8601DateFormatter.withFractionalSeconds.date(from: raw) {
                return d
            }
            if let d = ISO8601DateFormatter.internetDateTime.date(from: raw) {
                return d
            }
            throw SunnyAPIError.decodeFailure
        }

        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
    }

    func fetchSunny(area: SunnyArea, requestedTime: Date?) async throws -> SunnyFetchResult {
        var apiError: Error?

        if let apiBaseURL = AppConfig.apiBaseURL {
            do {
                let result = try await fetchFromAPI(baseURL: apiBaseURL, area: area, requestedTime: requestedTime)
                let cached = CachedSunnyPayload(fetchedAt: result.fetchedAt, response: result.response)
                try persistCache(cached, area: area)
                return result
            } catch {
                apiError = error
            }
        }

        do {
            let result = try await fetchFromSnapshots(area: area, requestedTime: requestedTime)
            let cached = CachedSunnyPayload(fetchedAt: result.fetchedAt, response: result.response)
            try persistCache(cached, area: area)
            return result
        } catch {
            if let cached = try? loadCache(area: area) {
                return SunnyFetchResult(
                    response: cached.response,
                    fetchedAt: cached.fetchedAt,
                    fromCache: true,
                    sunModelInterpolated: false
                )
            }
            if let apiError {
                throw apiError
            }
            throw error
        }
    }

    private func fetchFromAPI(
        baseURL: URL,
        area: SunnyArea,
        requestedTime: Date?
    ) async throws -> SunnyFetchResult {
        let url = try buildAPIURL(baseURL: baseURL, area: area, requestedTime: requestedTime)
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SunnyAPIError.badResponse(-1)
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw SunnyAPIError.badResponse(http.statusCode)
        }
        let payload = try decoder.decode(SunnyResponse.self, from: data)
        return SunnyFetchResult(
            response: payload,
            fetchedAt: Date(),
            fromCache: false,
            sunModelInterpolated: false
        )
    }

    private func fetchFromSnapshots(area: SunnyArea, requestedTime: Date?) async throws -> SunnyFetchResult {
        let url = try buildSnapshotURL(area: area)
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SunnyAPIError.badResponse(-1)
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw SunnyAPIError.badResponse(http.statusCode)
        }

        let payload = try decoder.decode(AreaSnapshotPayload.self, from: data)
        guard !payload.snapshots.isEmpty else {
            throw SunnyAPIError.emptySnapshot
        }

        let target = (requestedTime ?? Date()).clampedToPredictionWindow()
        let selectedResult = selectSnapshotForTarget(payload.snapshots, target: target)
        let selected = selectedResult.snapshot

        let responsePayload = SunnyResponse(
            time: selected.timeUTC,
            cloudCoverPct: selected.cloudCoverPct,
            count: selected.cafes.count,
            cafes: selected.cafes
        )
        return SunnyFetchResult(
            response: responsePayload,
            fetchedAt: payload.generatedAtUTC ?? Date(),
            fromCache: false,
            sunModelInterpolated: selectedResult.interpolated
        )
    }

    private func selectSnapshotForTarget(_ snapshots: [AreaSnapshot], target: Date) -> (snapshot: AreaSnapshot, interpolated: Bool) {
        let sorted = snapshots.sorted { $0.timeUTC < $1.timeUTC }
        guard let first = sorted.first else { return (snapshots[0], false) }
        guard let last = sorted.last else { return (first, false) }

        if target <= first.timeUTC { return (first, false) }
        if target >= last.timeUTC { return (last, false) }

        for i in 0 ..< (sorted.count - 1) {
            let lower = sorted[i]
            let upper = sorted[i + 1]
            if target == lower.timeUTC { return (lower, false) }
            if target == upper.timeUTC { return (upper, false) }
            if target > lower.timeUTC && target < upper.timeUTC {
                let span = upper.timeUTC.timeIntervalSince(lower.timeUTC)
                guard span > 0 else { return (lower, false) }
                let w = target.timeIntervalSince(lower.timeUTC) / span
                return (interpolate(lower: lower, upper: upper, weight: w, target: target), true)
            }
        }

        let nearest = sorted.min {
            abs($0.timeUTC.timeIntervalSince(target)) < abs($1.timeUTC.timeIntervalSince(target))
        } ?? first
        return (nearest, false)
    }

    private func interpolate(lower: AreaSnapshot, upper: AreaSnapshot, weight: Double, target: Date) -> AreaSnapshot {
        let clampedWeight = max(0.0, min(1.0, weight))
        let lowerByID = Dictionary(uniqueKeysWithValues: lower.cafes.map { ($0.id, $0) })
        let upperByID = Dictionary(uniqueKeysWithValues: upper.cafes.map { ($0.id, $0) })

        var merged: [SunnyCafe] = []
        var seen = Set<String>()

        for (id, a) in lowerByID {
            guard let b = upperByID[id] else {
                merged.append(a)
                seen.insert(id)
                continue
            }
            merged.append(interpolateCafe(a, b, weight: clampedWeight))
            seen.insert(id)
        }

        for (id, b) in upperByID where !seen.contains(id) {
            merged.append(b)
        }

        let cloud = lerp(lower.cloudCoverPct, upper.cloudCoverPct, clampedWeight)
        return AreaSnapshot(
            timeUTC: target,
            cloudCoverPct: cloud,
            cafes: merged
        )
    }

    private func interpolateCafe(_ a: SunnyCafe, _ b: SunnyCafe, weight: Double) -> SunnyCafe {
        let fraction = max(0.0, min(1.0, lerp(a.sunnyFraction, b.sunnyFraction, weight)))
        let score = lerp(a.sunnyScore, b.sunnyScore, weight)
        let elevation = lerp(a.sunElevationDeg, b.sunElevationDeg, weight)
        let azimuth = lerp(a.sunAzimuthDeg, b.sunAzimuthDeg, weight)
        let cloud = lerp(a.cloudCoverPct ?? 50.0, b.cloudCoverPct ?? 50.0, weight)

        return SunnyCafe(
            osmID: a.osmID ?? b.osmID,
            name: a.name,
            lon: a.lon,
            lat: a.lat,
            sunnyScore: score,
            sunnyFraction: fraction,
            inShadow: fraction <= 0.01,
            sunElevationDeg: elevation,
            sunAzimuthDeg: azimuth,
            cloudCoverPct: cloud
        )
    }

    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + ((b - a) * t)
    }

    private func buildAPIURL(baseURL: URL, area: SunnyArea, requestedTime: Date?) throws -> URL {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/sunny"),
            resolvingAgainstBaseURL: false
        )
        guard components != nil else { throw SunnyAPIError.invalidURL }

        let bbox = area.bbox
        var items: [URLQueryItem] = [
            URLQueryItem(name: "min_lon", value: String(format: "%.6f", bbox.minLon)),
            URLQueryItem(name: "min_lat", value: String(format: "%.6f", bbox.minLat)),
            URLQueryItem(name: "max_lon", value: String(format: "%.6f", bbox.maxLon)),
            URLQueryItem(name: "max_lat", value: String(format: "%.6f", bbox.maxLat)),
            URLQueryItem(name: "limit", value: String(AppConfig.requestLimit))
        ]

        if let requestedTime {
            let rounded = requestedTime.clampedToPredictionWindow()
            let dateString = ISO8601DateFormatter.internetDateTime.string(from: rounded)
            items.append(URLQueryItem(name: "time", value: dateString))
        }

        components?.queryItems = items
        guard let url = components?.url else {
            throw SunnyAPIError.invalidURL
        }
        return url
    }

    private func buildSnapshotURL(area: SunnyArea) throws -> URL {
        let components = URLComponents(
            url: AppConfig.snapshotBaseURL.appendingPathComponent("\(area.rawValue).json"),
            resolvingAgainstBaseURL: false
        )
        guard let url = components?.url else {
            throw SunnyAPIError.invalidURL
        }
        return url
    }

    private func cacheDirectory() throws -> URL {
        let caches = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = caches.appendingPathComponent("SunnySipsAPICache")
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func cacheURL(area: SunnyArea) throws -> URL {
        try cacheDirectory().appendingPathComponent("\(area.rawValue)-latest.json")
    }

    private func persistCache(_ payload: CachedSunnyPayload, area: SunnyArea) throws {
        let data = try encoder.encode(payload)
        let url = try cacheURL(area: area)
        try data.write(to: url, options: .atomic)
    }

    private func loadCache(area: SunnyArea) throws -> CachedSunnyPayload {
        let url = try cacheURL(area: area)
        guard fileManager.fileExists(atPath: url.path) else {
            throw SunnyAPIError.noCachedData
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(CachedSunnyPayload.self, from: data)
    }
}
