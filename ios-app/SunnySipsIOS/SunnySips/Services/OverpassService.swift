import Foundation
import CoreLocation

struct CafeExternalDetails: Codable {
    let openingHours: [String]
    let websiteURL: URL?
    let mapsURL: URL?
    let formattedAddress: String?
    let phone: String?
    let cuisine: String?
    let outdoorSeating: Bool?

    var menuText: String {
        if websiteURL != nil {
            return "Menu info is usually available on the cafe website."
        }
        return "Menu details unavailable from OpenStreetMap metadata."
    }
}

enum OverpassError: Error {
    case invalidURL
    case invalidResponse
    case noCandidate
}

private struct OverpassResponse: Decodable {
    let elements: [OverpassElement]
}

private struct OverpassElement: Decodable {
    let id: Int
    let lat: Double?
    let lon: Double?
    let center: OverpassCenter?
    let tags: [String: String]?
}

private struct OverpassCenter: Decodable {
    let lat: Double
    let lon: Double
}

private struct CachedOverpassPayload: Codable {
    let createdAt: Date
    let details: CafeExternalDetails
}

actor OverpassService {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func fetchDetails(for cafe: SunnyCafe) async throws -> CafeExternalDetails {
        if let cached = try? loadCache(for: cafe.id), Date().timeIntervalSince(cached.createdAt) < AppConfig.overpassCacheTTL {
            if let websiteURL = cached.details.websiteURL {
                CafeLogoDomainStore.shared.registerWebsiteURL(websiteURL, forCafeName: cafe.name)
            }
            return cached.details
        }

        let response = try await queryOverpass(for: cafe)
        guard let details = bestDetails(for: cafe, from: response.elements) else {
            throw OverpassError.noCandidate
        }

        if let websiteURL = details.websiteURL {
            CafeLogoDomainStore.shared.registerWebsiteURL(websiteURL, forCafeName: cafe.name)
        }

        try? persistCache(CachedOverpassPayload(createdAt: Date(), details: details), for: cafe.id)
        return details
    }

    private func queryOverpass(for cafe: SunnyCafe) async throws -> OverpassResponse {
        var request = URLRequest(url: AppConfig.overpassAPIURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let query = overpassQuery(lat: cafe.lat, lon: cafe.lon)
        let body = "data=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw OverpassError.invalidResponse
        }
        return try decoder.decode(OverpassResponse.self, from: data)
    }

    private func overpassQuery(lat: Double, lon: Double) -> String {
        """
        [out:json][timeout:12];
        (
          node(around:60,\(lat),\(lon))["amenity"="cafe"];
          way(around:60,\(lat),\(lon))["amenity"="cafe"];
        );
        out center tags;
        """
    }

    private func bestDetails(for cafe: SunnyCafe, from elements: [OverpassElement]) -> CafeExternalDetails? {
        let source = CLLocation(latitude: cafe.lat, longitude: cafe.lon)
        let targetName = cafe.name.normalizedForSearch

        var best: (score: Double, details: CafeExternalDetails)?

        for element in elements {
            let tags = element.tags ?? [:]
            let candidateName = (tags["name"] ?? "").normalizedForSearch
            guard !candidateName.isEmpty else { continue }

            let nameScore: Double
            if candidateName == targetName {
                nameScore = 1.0
            } else if candidateName.contains(targetName) || targetName.contains(candidateName) {
                nameScore = 0.8
            } else if candidateName.levenshteinDistance(to: targetName) <= 3 {
                nameScore = 0.6
            } else {
                nameScore = 0.2
            }

            let coordinate = elementCoordinate(element)
            let distanceScore: Double
            if let coordinate {
                let dist = source.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
                distanceScore = max(0.0, 1.0 - (dist / 120.0))
            } else {
                distanceScore = 0.2
            }

            let final = (nameScore * 0.75) + (distanceScore * 0.25)
            let details = mapDetails(tags: tags)

            if let current = best {
                if final > current.score {
                    best = (final, details)
                }
            } else {
                best = (final, details)
            }
        }

        return best?.details
    }

    private func mapDetails(tags: [String: String]) -> CafeExternalDetails {
        let hoursRaw = tags["opening_hours"] ?? ""
        let hoursLines: [String]
        if hoursRaw.isEmpty {
            hoursLines = []
        } else {
            hoursLines = hoursRaw
                .replacingOccurrences(of: ";", with: "; ")
                .split(separator: ";")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        let website = tags["website"] ?? tags["contact:website"]
        let phone = tags["phone"] ?? tags["contact:phone"]
        let cuisine = tags["cuisine"]
        let outdoor = tags["outdoor_seating"].map { $0.lowercased() == "yes" }

        let street = tags["addr:street"]
        let house = tags["addr:housenumber"]
        let city = tags["addr:city"]
        let addressParts = [street, house, city].compactMap { $0 }.filter { !$0.isEmpty }
        let address = addressParts.isEmpty ? nil : addressParts.joined(separator: " ")

        let mapsURL: URL?
        if let website, let url = URL(string: website) {
            mapsURL = url
        } else {
            mapsURL = nil
        }

        return CafeExternalDetails(
            openingHours: hoursLines,
            websiteURL: website.flatMap(URL.init(string:)),
            mapsURL: mapsURL,
            formattedAddress: address,
            phone: phone,
            cuisine: cuisine,
            outdoorSeating: outdoor
        )
    }

    private func elementCoordinate(_ element: OverpassElement) -> CLLocationCoordinate2D? {
        if let lat = element.lat, let lon = element.lon {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        if let center = element.center {
            return CLLocationCoordinate2D(latitude: center.lat, longitude: center.lon)
        }
        return nil
    }

    private func cacheURL(for id: String) throws -> URL {
        let cache = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = cache.appendingPathComponent("SunnySipsOverpassCache", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let safe = id.replacingOccurrences(of: "/", with: "-")
        return dir.appendingPathComponent("\(safe).json")
    }

    private func persistCache(_ payload: CachedOverpassPayload, for id: String) throws {
        let data = try encoder.encode(payload)
        try data.write(to: cacheURL(for: id), options: .atomic)
    }

    private func loadCache(for id: String) throws -> CachedOverpassPayload {
        let data = try Data(contentsOf: cacheURL(for: id))
        return try decoder.decode(CachedOverpassPayload.self, from: data)
    }
}
