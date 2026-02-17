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
                return SunnyFetchResult(response: cached.response, fetchedAt: cached.fetchedAt, fromCache: true)
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
        return SunnyFetchResult(response: payload, fetchedAt: Date(), fromCache: false)
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

        let target = (requestedTime ?? Date()).clampedToToday().roundedToQuarterHour()
        let selected = payload.snapshots.min {
            abs($0.timeUTC.timeIntervalSince(target)) < abs($1.timeUTC.timeIntervalSince(target))
        } ?? payload.snapshots[0]

        let responsePayload = SunnyResponse(
            time: selected.timeUTC,
            cloudCoverPct: selected.cloudCoverPct,
            count: selected.cafes.count,
            cafes: selected.cafes
        )
        return SunnyFetchResult(
            response: responsePayload,
            fetchedAt: payload.generatedAtUTC ?? Date(),
            fromCache: false
        )
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
            let rounded = requestedTime.clampedToToday().roundedToQuarterHour()
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
