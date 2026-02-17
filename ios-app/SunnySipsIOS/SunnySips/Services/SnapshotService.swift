import Foundation

enum SnapshotServiceError: LocalizedError {
    case invalidResponse
    case noCache(URL)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from snapshot server."
        case .noCache(let url):
            return "No cached data for \(url.lastPathComponent)."
        }
    }
}

actor SnapshotService {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let fileManager: FileManager

    init(session: URLSession = .shared) {
        self.session = session
        self.fileManager = .default
        self.decoder = JSONDecoder()
    }

    func fetchIndex(baseURL: URL) async throws -> SnapshotIndex {
        try await fetchAndCacheJSON(pathComponent: "index.json", baseURL: baseURL, as: SnapshotIndex.self)
    }

    func fetchAreaSnapshot(fileName: String, baseURL: URL) async throws -> AreaSnapshotFile {
        try await fetchAndCacheJSON(pathComponent: fileName, baseURL: baseURL, as: AreaSnapshotFile.self)
    }

    private func fetchAndCacheJSON<T: Decodable>(
        pathComponent: String,
        baseURL: URL,
        as _: T.Type
    ) async throws -> T {
        let url = baseURL.appendingPathComponent(pathComponent)
        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) else {
                throw SnapshotServiceError.invalidResponse
            }
            try cache(data: data, for: pathComponent)
            return try decoder.decode(T.self, from: data)
        } catch {
            let cached = try loadCachedData(for: pathComponent)
            return try decoder.decode(T.self, from: cached)
        }
    }

    private func cache(data: Data, for pathComponent: String) throws {
        let url = try cacheURL(for: pathComponent)
        let dir = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try data.write(to: url, options: .atomic)
    }

    private func loadCachedData(for pathComponent: String) throws -> Data {
        let url = try cacheURL(for: pathComponent)
        guard fileManager.fileExists(atPath: url.path) else {
            throw SnapshotServiceError.noCache(url)
        }
        return try Data(contentsOf: url)
    }

    private func cacheURL(for pathComponent: String) throws -> URL {
        let caches = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return caches.appendingPathComponent("SunnySipsSnapshots").appendingPathComponent(pathComponent)
    }
}

