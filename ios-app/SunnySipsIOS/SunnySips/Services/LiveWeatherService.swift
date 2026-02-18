import Foundation

enum LiveWeatherError: Error {
    case invalidURL
    case invalidResponse
    case noData
}

struct LiveWeatherReading {
    let cloudCoverPct: Double
    let fetchedAt: Date
    let source: String
    let isForecast: Bool
    let targetTime: Date
}

private struct OpenMeteoResponse: Decodable {
    let hourly: OpenMeteoHourly
}

private struct OpenMeteoHourly: Decodable {
    let time: [String]
    let cloudcover: [Double]?
    let cloudCover: [Double]?

    enum CodingKeys: String, CodingKey {
        case time
        case cloudcover
        case cloudCover = "cloud_cover"
    }
}

private struct MetNoResponse: Decodable {
    let properties: MetNoProperties
}

private struct MetNoProperties: Decodable {
    let timeseries: [MetNoTimeSeries]
}

private struct MetNoTimeSeries: Decodable {
    let time: String
    let data: MetNoData
}

private struct MetNoData: Decodable {
    let instant: MetNoInstant

    enum CodingKeys: String, CodingKey {
        case instant
    }
}

private struct MetNoInstant: Decodable {
    let details: MetNoInstantDetails
}

private struct MetNoInstantDetails: Decodable {
    let cloudAreaFraction: Double?

    enum CodingKeys: String, CodingKey {
        case cloudAreaFraction = "cloud_area_fraction"
    }
}

actor LiveWeatherService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchCloudCover(area: SunnyArea, at date: Date) async throws -> LiveWeatherReading {
        do {
            return try await fetchFromOpenMeteo(area: area, date: date)
        } catch {
            return try await fetchFromMetNo(area: area, date: date)
        }
    }

    private func fetchFromOpenMeteo(area: SunnyArea, date: Date) async throws -> LiveWeatherReading {
        guard let url = buildOpenMeteoURL(area: area, date: date) else {
            throw LiveWeatherError.invalidURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw LiveWeatherError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        let clouds = decoded.hourly.cloudcover ?? decoded.hourly.cloudCover ?? []
        guard !decoded.hourly.time.isEmpty, !clouds.isEmpty else {
            throw LiveWeatherError.noData
        }

        let parsed = zip(decoded.hourly.time, clouds).compactMap { raw, cloud -> (Date, Double)? in
            guard let parsedDate = parseLocalHour(raw) else { return nil }
            return (parsedDate, max(0, min(100, cloud)))
        }
        guard !parsed.isEmpty else { throw LiveWeatherError.noData }

        let nearest = parsed.min {
            abs($0.0.timeIntervalSince(date)) < abs($1.0.timeIntervalSince(date))
        } ?? parsed[0]

        return LiveWeatherReading(
            cloudCoverPct: nearest.1,
            fetchedAt: Date(),
            source: "Open-Meteo",
            isForecast: date > Date().addingTimeInterval(15 * 60),
            targetTime: nearest.0
        )
    }

    private func fetchFromMetNo(area: SunnyArea, date: Date) async throws -> LiveWeatherReading {
        guard let url = buildMetNoURL(area: area) else {
            throw LiveWeatherError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("SunnySips/1.0 (ios)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw LiveWeatherError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(MetNoResponse.self, from: data)
        guard !decoded.properties.timeseries.isEmpty else { throw LiveWeatherError.noData }

        var candidates: [(Date, Double)] = []
        for point in decoded.properties.timeseries {
            guard let dt = ISO8601DateFormatter.internetDateTime.date(from: point.time) ??
                ISO8601DateFormatter.withFractionalSeconds.date(from: point.time)
            else { continue }

            if let cloud = point.data.instant.details.cloudAreaFraction {
                candidates.append((dt, max(0, min(100, cloud))))
            }
        }
        guard !candidates.isEmpty else { throw LiveWeatherError.noData }

        let nearest = candidates.min {
            abs($0.0.timeIntervalSince(date)) < abs($1.0.timeIntervalSince(date))
        } ?? candidates[0]

        return LiveWeatherReading(
            cloudCoverPct: nearest.1,
            fetchedAt: Date(),
            source: "MET Norway",
            isForecast: date > Date().addingTimeInterval(15 * 60),
            targetTime: nearest.0
        )
    }

    private func buildOpenMeteoURL(area: SunnyArea, date: Date) -> URL? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        let center = area.bbox.center

        let dateFormatter = DateFormatter()
        dateFormatter.calendar = Date.copenhagenCalendar
        dateFormatter.timeZone = TimeZone(identifier: "Europe/Copenhagen")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let day = dateFormatter.string(from: date)

        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.6f", center.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.6f", center.longitude)),
            URLQueryItem(name: "hourly", value: "cloudcover"),
            URLQueryItem(name: "timezone", value: "Europe/Copenhagen"),
            URLQueryItem(name: "start_date", value: day),
            URLQueryItem(name: "end_date", value: day),
        ]
        return components?.url
    }

    private func buildMetNoURL(area: SunnyArea) -> URL? {
        var components = URLComponents(string: "https://api.met.no/weatherapi/locationforecast/2.0/compact")
        let center = area.bbox.center
        components?.queryItems = [
            URLQueryItem(name: "lat", value: String(format: "%.6f", center.latitude)),
            URLQueryItem(name: "lon", value: String(format: "%.6f", center.longitude)),
        ]
        return components?.url
    }

    private func parseLocalHour(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Date.copenhagenCalendar
        formatter.timeZone = TimeZone(identifier: "Europe/Copenhagen")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        if let parsed = formatter.date(from: raw) {
            return parsed
        }
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: raw)
    }
}
