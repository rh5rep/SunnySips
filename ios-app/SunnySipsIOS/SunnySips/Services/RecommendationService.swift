import Foundation
import os

enum RecommendationServiceError: LocalizedError {
    case missingAPIBaseURL
    case invalidURL
    case invalidResponse
    case decodingFailed
    case temporarilyUnavailable
    case serverError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .missingAPIBaseURL: return "Recommendation API URL is not configured."
        case .invalidURL: return "Recommendation API URL is invalid."
        case .invalidResponse: return "Recommendation API returned an invalid response."
        case .decodingFailed: return "Could not decode recommendation payload."
        case .temporarilyUnavailable: return "Temporarily unavailable—check connection."
        case .serverError(let statusCode): return "Server error (\(statusCode))."
        }
    }
}

actor RecommendationService {
    private let session: URLSession
    private let snapshotService = SunnyAPIService()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let freshTTLHours: Double = 2
    private let staleTTLHours: Double = 12
    private let logger = Logger(subsystem: "SunnySips", category: "RecommendationService")

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchCafeSunOutlook(
        cafeId: String,
        cityId: String,
        days: Int = 5,
        include: [String] = ["hourly", "windows"],
        minDuration: Int = 30
    ) async throws -> CafeSunOutlookResponse {
        _ = include
        return try await fetchCafeSunWindows(
            cafeId: cafeId,
            cityId: cityId,
            days: days,
            minDuration: minDuration
        )
    }

    func fetchCafeSunWindows(
        cafeId: String,
        cityId: String,
        days: Int = 5,
        minDuration: Int = 30
    ) async throws -> CafeSunOutlookResponse {
        _ = cityId
        let effectiveCityId = "copenhagen"
        let cappedDays = max(1, min(5, days))
        let cacheKey = "sun-series-\(effectiveCityId)-\(cafeId)-\(cappedDays)-\(max(0, minDuration))"
        if apiBaseURL == nil,
           let staticOutlook = try? await fetchFromSnapshotPages(
               cafeId: cafeId,
               cityId: effectiveCityId,
               days: cappedDays,
               minDuration: minDuration
           ) {
            logger.debug("Using snapshot-pages outlook because API base URL is not configured")
            print("[RecommendationService] using snapshot-pages outlook (no API base URL)")
            let cachedPayload = try encoder.encode(staticOutlook)
            try saveCache(cacheKey: cacheKey, data: cachedPayload)
            return staticOutlook
        }
        do {
            let url = try buildSunSeriesURL(
                cafeId: cafeId,
                cityId: effectiveCityId,
                days: cappedDays
            )
            var payloadData: Data
            do {
                payloadData = try await requestPayload(url: url, endpointName: "sun-series")
            } catch RecommendationServiceError.serverError(let statusCode) where statusCode == 404 {
                let legacyURL = try buildLegacySunOutlookURL(
                    cafeId: cafeId,
                    cityId: effectiveCityId,
                    days: min(5, cappedDays),
                    minDuration: minDuration
                )
                logger.debug("sun-series unavailable; falling back to sun-outlook URL: \(legacyURL.absoluteString, privacy: .public)")
                payloadData = try await requestPayload(url: legacyURL, endpointName: "sun-outlook")
            }

            let decoded = try decodeSunSeriesPayload(
                data: payloadData,
                requestedCafeID: cafeId,
                requestedCityID: effectiveCityId,
                minDuration: minDuration
            )
            var bestResponse = decoded
            let primaryCoverage = outlookCoverageDays(decoded.hourly)

            if primaryCoverage < cappedDays {
                let legacyURL = try buildLegacySunOutlookURL(
                    cafeId: cafeId,
                    cityId: effectiveCityId,
                    days: min(5, cappedDays),
                    minDuration: minDuration
                )
                if let legacyData = try? await requestPayload(url: legacyURL, endpointName: "sun-outlook"),
                   let legacyDecoded = try? decodeSunSeriesPayload(
                       data: legacyData,
                       requestedCafeID: cafeId,
                       requestedCityID: effectiveCityId,
                       minDuration: minDuration
                   ) {
                    let legacyCoverage = outlookCoverageDays(legacyDecoded.hourly)
                    if legacyCoverage > primaryCoverage {
                        logger.debug("Using sun-outlook payload with broader horizon days=\(legacyCoverage)")
                        bestResponse = legacyDecoded
                    }
                }
            }
            let cachedPayload = try encoder.encode(bestResponse)
            try saveCache(cacheKey: cacheKey, data: cachedPayload)
            return bestResponse
        } catch {
            logger.error("Sun-series fetch failed: \(String(describing: error), privacy: .public)")
            print("[RecommendationService] sun fetch failed cafe=\(cafeId) city=\(effectiveCityId) error=\(error)")
            if let cached = try? loadCachedData(cacheKey: cacheKey),
               let decoded = try? decoder.decode(CafeSunOutlookResponse.self, from: cached.data),
               cached.ageHours <= staleTTLHours {
                logger.debug("Sun-series using disk cache age=\(cached.ageHours, privacy: .public)h")
                print("[RecommendationService] using stale cache provider=\(decoded.providerUsed ?? "none") ageHours=\(cached.ageHours)")
                return staleOutlook(decoded, ageHours: cached.ageHours)
            }
            if let staticOutlook = try? await fetchFromSnapshotPages(
                cafeId: cafeId,
                cityId: effectiveCityId,
                days: cappedDays,
                minDuration: minDuration
            ) {
                logger.debug("Using snapshot-pages outlook after API failure")
                print("[RecommendationService] using snapshot-pages outlook after API failure")
                let cachedPayload = try encoder.encode(staticOutlook)
                try saveCache(cacheKey: cacheKey, data: cachedPayload)
                return staticOutlook
            }
            if let fallback = try? await fallbackFromShortTermSnapshotWeather(
                cafeId: cafeId,
                cityId: effectiveCityId,
                minDuration: minDuration
            ) {
                logger.debug("Sun-series using weather snapshot fallback")
                print("[RecommendationService] using snapshot weather fallback")
                return fallback
            }
            if let serviceError = error as? RecommendationServiceError {
                switch serviceError {
                case .serverError, .invalidResponse:
                    throw RecommendationServiceError.temporarilyUnavailable
                default:
                    throw serviceError
                }
            }
            if error is URLError {
                throw RecommendationServiceError.temporarilyUnavailable
            }
            throw RecommendationServiceError.temporarilyUnavailable
        }
    }

    func fetchFavoriteRecommendations(
        cafeIds: [String],
        cityId: String,
        days: Int = 5,
        prefs: RecommendationPrefsPayload
    ) async throws -> FavoritesRecommendationResponse {
        let sortedCafeIDs = cafeIds.sorted()
        let cacheKey = "favorites-\(cityId)-\(days)-\(sortedCafeIDs.joined(separator: "_"))-\(prefs.minDurationMin)-\(prefs.preferredPeriods.sorted().joined(separator: "_"))"
        if apiBaseURL == nil,
           let staticRecs = try? await fetchFavoriteRecommendationsFromSnapshotPages(
               cafeIds: sortedCafeIDs,
               cityId: cityId,
               days: days,
               prefs: prefs
           ) {
            print("[RecommendationService] using snapshot-pages recommendations (no API base URL)")
            let cachedPayload = try encoder.encode(staticRecs)
            try saveCache(cacheKey: cacheKey, data: cachedPayload)
            return staticRecs
        }
        do {
            let url = try buildRecommendationsURL()
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 25
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body = FavoritesRecommendationRequestPayload(
                cityID: cityId,
                favoriteIDs: sortedCafeIDs,
                days: max(1, min(5, days)),
                prefs: prefs
            )
            request.httpBody = try encoder.encode(body)

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                throw RecommendationServiceError.invalidResponse
            }
            let decoded = try decoder.decode(FavoritesRecommendationResponse.self, from: data)
            try saveCache(cacheKey: cacheKey, data: data)
            return decoded
        } catch {
            print("[RecommendationService] recommendations fetch failed city=\(cityId) favorites=\(sortedCafeIDs.count) error=\(error)")
            if let cached = try? loadCachedData(cacheKey: cacheKey),
               let decoded = try? decoder.decode(FavoritesRecommendationResponse.self, from: cached.data),
               cached.ageHours <= staleTTLHours {
                print("[RecommendationService] using stale recommendations cache ageHours=\(cached.ageHours)")
                return staleRecommendations(decoded, ageHours: cached.ageHours)
            }
            if let staticRecs = try? await fetchFavoriteRecommendationsFromSnapshotPages(
                cafeIds: sortedCafeIDs,
                cityId: cityId,
                days: days,
                prefs: prefs
            ) {
                print("[RecommendationService] using snapshot-pages recommendations after API failure")
                let cachedPayload = try encoder.encode(staticRecs)
                try saveCache(cacheKey: cacheKey, data: cachedPayload)
                return staticRecs
            }
            throw error
        }
    }

    private func buildSunSeriesURL(
        cafeId: String,
        cityId: String,
        days: Int
    ) throws -> URL {
        guard let base = apiBaseURL else { throw RecommendationServiceError.missingAPIBaseURL }
        var components = URLComponents(
            url: base.appendingPathComponent("api/cafe/\(cafeId)/sun-series"),
            resolvingAgainstBaseURL: false
        )
        guard components != nil else { throw RecommendationServiceError.invalidURL }

        components?.queryItems = [
            URLQueryItem(name: "city_id", value: cityId),
            URLQueryItem(name: "days", value: String(max(1, min(5, days)))),
        ]
        guard let url = components?.url else { throw RecommendationServiceError.invalidURL }
        return url
    }

    private func buildLegacySunOutlookURL(
        cafeId: String,
        cityId: String,
        days: Int,
        minDuration: Int
    ) throws -> URL {
        guard let base = apiBaseURL else { throw RecommendationServiceError.missingAPIBaseURL }
        var components = URLComponents(
            url: base.appendingPathComponent("api/cafe/\(cafeId)/sun-outlook"),
            resolvingAgainstBaseURL: false
        )
        guard components != nil else { throw RecommendationServiceError.invalidURL }

        components?.queryItems = [
            URLQueryItem(name: "city_id", value: cityId),
            URLQueryItem(name: "days", value: String(max(1, min(5, days)))),
            URLQueryItem(name: "include", value: "hourly,windows"),
            URLQueryItem(name: "min_duration_min", value: String(max(0, minDuration))),
        ]
        guard let url = components?.url else { throw RecommendationServiceError.invalidURL }
        return url
    }

    private func requestPayload(url: URL, endpointName: String) async throws -> Data {
        logger.debug("\(endpointName, privacy: .public) request URL: \(url.absoluteString, privacy: .public)")
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            logger.error("\(endpointName, privacy: .public) invalid HTTP response")
            throw RecommendationServiceError.invalidResponse
        }
        logger.debug("\(endpointName, privacy: .public) status=\(http.statusCode)")
        guard (200 ... 299).contains(http.statusCode) else {
            let body = String(data: data.prefix(400), encoding: .utf8) ?? "<non-utf8>"
            logger.error("\(endpointName, privacy: .public) non-2xx status=\(http.statusCode), body=\(body, privacy: .public)")
            throw RecommendationServiceError.serverError(statusCode: http.statusCode)
        }
        return data
    }

    private func buildRecommendationsURL() throws -> URL {
        guard let base = apiBaseURL else { throw RecommendationServiceError.missingAPIBaseURL }
        let url = base.appendingPathComponent("api/recommendations/favorites")
        return url
    }

    private func buildSnapshotPagesOutlookURL() -> URL {
        AppConfig.snapshotBaseURL.appendingPathComponent("core-cph.json")
    }

    private var apiBaseURL: URL? {
        if let explicit = AppConfig.recommendationAPIBaseURL {
            return explicit
        }
        return AppConfig.apiBaseURL
    }

    private struct CachedBlob: Codable {
        let savedAt: Date
        let payload: Data
    }

    private func cacheDirectory() throws -> URL {
        let cacheRoot = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = cacheRoot.appendingPathComponent("SunnySipsRecommendations", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func cacheURL(for key: String) throws -> URL {
        let safe = key.replacingOccurrences(of: "/", with: "_")
        return try cacheDirectory().appendingPathComponent("\(safe).json")
    }

    private func saveCache(cacheKey: String, data: Data) throws {
        let blob = CachedBlob(savedAt: Date(), payload: data)
        let encoded = try encoder.encode(blob)
        try encoded.write(to: cacheURL(for: cacheKey), options: .atomic)
    }

    private func loadCachedData(cacheKey: String) throws -> (data: Data, ageHours: Double) {
        let data = try Data(contentsOf: cacheURL(for: cacheKey))
        let blob = try decoder.decode(CachedBlob.self, from: data)
        let ageHours = max(0, Date().timeIntervalSince(blob.savedAt) / 3600.0)
        return (blob.payload, ageHours)
    }

    private func staleOutlook(_ base: CafeSunOutlookResponse, ageHours: Double) -> CafeSunOutlookResponse {
        CafeSunOutlookResponse(
            cafeID: base.cafeID,
            cityID: base.cityID,
            timezone: base.timezone,
            dataStatus: ageHours <= freshTTLHours ? .fresh : .stale,
            freshnessHours: ageHours,
            providerUsed: base.providerUsed,
            fallbackUsed: true,
            hourly: base.hourly,
            windows: base.windows,
            generatedAtUTC: base.generatedAtUTC
        )
    }

    private func staleRecommendations(_ base: FavoritesRecommendationResponse, ageHours: Double) -> FavoritesRecommendationResponse {
        FavoritesRecommendationResponse(
            cityID: base.cityID,
            timezone: base.timezone,
            dataStatus: ageHours <= freshTTLHours ? .fresh : .stale,
            freshnessHours: ageHours,
            providerUsed: base.providerUsed,
            fallbackUsed: true,
            items: base.items,
            generatedAtUTC: base.generatedAtUTC
        )
    }

    private struct SunSeriesResponse: Codable {
        let cafeID: String?
        let cityID: String?
        let timezone: String?
        let dataStatus: RecommendationDataStatus?
        let freshnessHours: Double?
        let providerUsed: String?
        let fallbackUsed: Bool?
        let hourly: [SunOutlookHourlyPoint]?
        let windows: [SunOutlookWindow]?
        let generatedAtUTC: String?

        enum CodingKeys: String, CodingKey {
            case cafeID = "cafe_id"
            case cityID = "city_id"
            case timezone
            case dataStatus = "data_status"
            case freshnessHours = "freshness_hours"
            case providerUsed = "provider_used"
            case fallbackUsed = "fallback_used"
            case hourly
            case windows
            case generatedAtUTC = "generated_at_utc"
        }
    }

    private func decodeSunSeriesPayload(
        data: Data,
        requestedCafeID: String,
        requestedCityID: String,
        minDuration: Int
    ) throws -> CafeSunOutlookResponse {
        if let decoded = try? decoder.decode(CafeSunOutlookResponse.self, from: data) {
            let normalizedHourly = normalizeHourlyPoints(decoded.hourly)
            return CafeSunOutlookResponse(
                cafeID: decoded.cafeID,
                cityID: decoded.cityID,
                timezone: decoded.timezone,
                dataStatus: decoded.dataStatus,
                freshnessHours: decoded.freshnessHours,
                providerUsed: decoded.providerUsed,
                fallbackUsed: decoded.fallbackUsed,
                hourly: normalizedHourly,
                windows: mergeHourlyIntoWindows(normalizedHourly, minDuration: minDuration),
                generatedAtUTC: decoded.generatedAtUTC
            )
        }
        let raw = try decoder.decode(SunSeriesResponse.self, from: data)
        let hourly = (raw.hourly ?? []).sorted {
            parseISODate($0.timeUTC) ?? .distantPast < parseISODate($1.timeUTC) ?? .distantPast
        }
        let normalizedHourly = normalizeHourlyPoints(hourly)
        let windows = mergeHourlyIntoWindows(normalizedHourly, minDuration: minDuration)

        return CafeSunOutlookResponse(
            cafeID: raw.cafeID ?? requestedCafeID,
            cityID: raw.cityID ?? requestedCityID,
            timezone: raw.timezone ?? "Europe/Copenhagen",
            dataStatus: raw.dataStatus ?? .fresh,
            freshnessHours: raw.freshnessHours,
            providerUsed: raw.providerUsed,
            fallbackUsed: raw.fallbackUsed ?? false,
            hourly: normalizedHourly,
            windows: windows,
            generatedAtUTC: raw.generatedAtUTC ?? iso8601UTCString(Date())
        )
    }

    private func mergeHourlyIntoWindows(_ hourly: [SunOutlookHourlyPoint], minDuration: Int) -> [SunOutlookWindow] {
        guard !hourly.isEmpty else { return [] }
        var windows: [SunOutlookWindow] = []
        var startIndex: Int?
        var hasSunny = false

        for index in hourly.indices {
            let pointCondition = canonicalCondition(
                rawCondition: hourly[index].condition,
                score: hourly[index].score,
                cloudCoverPct: hourly[index].cloudCoverPct,
                sunElevationDeg: nil
            )
            let isSunAvailable = isSunWindowCondition(pointCondition)
            if isSunAvailable {
                if startIndex == nil {
                    startIndex = index
                    hasSunny = pointCondition == "sunny"
                } else if pointCondition == "sunny" {
                    hasSunny = true
                }
            }

            let shouldCloseWindow = startIndex != nil && (!isSunAvailable || index == hourly.count - 1)
            guard shouldCloseWindow, let start = startIndex else { continue }
            let end = (isSunAvailable && index == hourly.count - 1) ? index : (index - 1)
            if let window = buildWindow(
                hourly: hourly,
                startIndex: start,
                endIndex: end,
                minDuration: minDuration,
                hasSunny: hasSunny
            ) {
                windows.append(window)
            }
            startIndex = nil
            hasSunny = false
        }

        return windows
    }

    private func buildWindow(
        hourly: [SunOutlookHourlyPoint],
        startIndex: Int,
        endIndex: Int,
        minDuration: Int,
        hasSunny: Bool
    ) -> SunOutlookWindow? {
        guard startIndex >= 0, endIndex >= startIndex, endIndex < hourly.count else { return nil }
        guard let startDateUTC = parseISODate(hourly[startIndex].timeUTC) else { return nil }

        let endDateUTC: Date
        let endUTC: String
        let endLocal: String
        if endIndex + 1 < hourly.count, let nextDateUTC = parseISODate(hourly[endIndex + 1].timeUTC) {
            endDateUTC = nextDateUTC
            endUTC = hourly[endIndex + 1].timeUTC
            endLocal = hourly[endIndex + 1].timeLocal
        } else {
            endDateUTC = startDateUTC.addingTimeInterval(Double((endIndex - startIndex + 1) * 3600))
            endUTC = iso8601UTCString(endDateUTC)
            endLocal = iso8601LocalString(endDateUTC, timezoneID: hourly[endIndex].timezone)
        }

        let durationMin = Int(max(0, endDateUTC.timeIntervalSince(startDateUTC)) / 60.0)
        guard durationMin >= max(0, minDuration) else { return nil }

        return SunOutlookWindow(
            startUTC: hourly[startIndex].timeUTC,
            endUTC: endUTC,
            startLocal: hourly[startIndex].timeLocal,
            endLocal: endLocal,
            durationMin: durationMin,
            condition: hasSunny ? "sunny" : "partial"
        )
    }

    private func isSunWindowCondition(_ condition: String) -> Bool {
        let normalized = condition.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "sunny" || normalized == "partial"
    }

    private func parseISODate(_ raw: String) -> Date? {
        if let withFractional = ISO8601DateFormatter.withFractionalSeconds.date(from: raw) {
            return withFractional
        }
        return ISO8601DateFormatter.internetDateTime.date(from: raw)
    }

    private func iso8601UTCString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private func iso8601LocalString(_ date: Date, timezoneID: String?) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timezoneID.flatMap(TimeZone.init(identifier:)) ?? TimeZone(identifier: "Europe/Copenhagen")
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private func fallbackFromShortTermSnapshotWeather(
        cafeId: String,
        cityId: String,
        minDuration: Int
    ) async throws -> CafeSunOutlookResponse? {
        var hourlyPoints: [SunOutlookHourlyPoint] = []
        let base = Date().roundedDownToQuarterHour()
        for hourOffset in 0 ... 6 {
            let target = base.addingTimeInterval(Double(hourOffset) * 3600)
            guard let point = try await snapshotHourlyPoint(for: cafeId, target: target) else { continue }
            if hourlyPoints.last?.timeUTC != point.timeUTC {
                hourlyPoints.append(point)
            }
        }
        guard !hourlyPoints.isEmpty else { return nil }
        return CafeSunOutlookResponse(
            cafeID: cafeId,
            cityID: cityId,
            timezone: "Europe/Copenhagen",
            dataStatus: .stale,
            freshnessHours: nil,
            providerUsed: "snapshot-cache",
            fallbackUsed: true,
            hourly: hourlyPoints,
            windows: mergeHourlyIntoWindows(hourlyPoints, minDuration: minDuration),
            generatedAtUTC: iso8601UTCString(Date())
        )
    }

    private func snapshotHourlyPoint(for cafeId: String, target: Date) async throws -> SunOutlookHourlyPoint? {
        for area in SunnyArea.allCases {
            guard let result = try? await snapshotService.fetchSunny(area: area, requestedTime: target) else { continue }
            guard let cafe = result.response.cafes.first(where: { $0.id == cafeId }) else { continue }
            let cloud = result.response.cloudCoverPct
            let score = cafe.sunnyScore(at: target, cloudCover: cloud)
            let condition = canonicalCondition(
                rawCondition: cafe.effectiveCondition(at: target, cloudCover: cloud).rawValue.lowercased(),
                score: score,
                cloudCoverPct: cloud,
                sunElevationDeg: cafe.sunElevationDeg
            )
            return SunOutlookHourlyPoint(
                timeUTC: iso8601UTCString(target),
                timeLocal: iso8601LocalString(target, timezoneID: "Europe/Copenhagen"),
                timezone: "Europe/Copenhagen",
                condition: condition,
                score: score,
                confidenceHint: 0.5,
                cloudCoverPct: cloud
            )
        }
        return nil
    }

    private func outlookCoverageDays(_ hourly: [SunOutlookHourlyPoint]) -> Int {
        guard !hourly.isEmpty else { return 0 }
        let days = Set(hourly.map { String($0.timeLocal.prefix(10)) })
        return days.count
    }

    private func fetchFromSnapshotPages(
        cafeId: String,
        cityId: String,
        days: Int,
        minDuration: Int
    ) async throws -> CafeSunOutlookResponse? {
        let url = buildSnapshotPagesOutlookURL()
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            return nil
        }

        let payload = try decoder.decode(PagesAreaSnapshotPayload.self, from: data)
        let requestedOsmID = parseOsmID(from: cafeId)

        let matchedRows: [PagesMatchedPoint] = payload.snapshots.compactMap { snapshot in
            guard let cafeRow = matchSnapshotCafe(snapshot.cafes, cafeId: cafeId, requestedOsmID: requestedOsmID) else {
                return nil
            }
            return PagesMatchedPoint(snapshot: snapshot, cafe: cafeRow)
        }

        guard !matchedRows.isEmpty else { return nil }
        let sorted = matchedRows.sorted {
            parseISODate($0.snapshot.timeUTC) ?? .distantPast < parseISODate($1.snapshot.timeUTC) ?? .distantPast
        }
        let maxHours = max(24, days * 24)
        let hourly = sorted.prefix(maxHours).map { point in
            let cloud = point.cafe.cloudCoverPct ?? point.snapshot.cloudCoverPct
            let condition = canonicalCondition(
                rawCondition: nil,
                score: point.cafe.sunnyScore,
                cloudCoverPct: cloud,
                sunElevationDeg: point.cafe.sunElevationDeg
            )
            let hoursAhead = max(
                0.0,
                ((parseISODate(point.snapshot.timeUTC) ?? Date()).timeIntervalSince(Date())) / 3600.0
            )
            return SunOutlookHourlyPoint(
                timeUTC: point.snapshot.timeUTC,
                timeLocal: point.snapshot.timeLocal,
                timezone: "Europe/Copenhagen",
                condition: condition,
                score: point.cafe.sunnyScore,
                confidenceHint: confidenceHint(hoursAhead: hoursAhead),
                cloudCoverPct: cloud
            )
        }

        guard !hourly.isEmpty else { return nil }
        let windows = mergeHourlyIntoWindows(hourly, minDuration: minDuration)
        let generatedDate = payload.generatedAtUTC.flatMap(parseISODate)
        let ageHours = generatedDate.map { max(0.0, Date().timeIntervalSince($0) / 3600.0) }
        let status: RecommendationDataStatus = (ageHours ?? 0.0) <= freshTTLHours ? .fresh : .stale

        return CafeSunOutlookResponse(
            cafeID: cafeId,
            cityID: cityId,
            timezone: "Europe/Copenhagen",
            dataStatus: status,
            freshnessHours: ageHours,
            providerUsed: "snapshot-pages",
            fallbackUsed: true,
            hourly: hourly,
            windows: windows,
            generatedAtUTC: payload.generatedAtUTC ?? iso8601UTCString(Date())
        )
    }

    private func fetchFavoriteRecommendationsFromSnapshotPages(
        cafeIds: [String],
        cityId: String,
        days: Int,
        prefs: RecommendationPrefsPayload
    ) async throws -> FavoritesRecommendationResponse? {
        guard !cafeIds.isEmpty else {
            return FavoritesRecommendationResponse(
                cityID: cityId,
                timezone: "Europe/Copenhagen",
                dataStatus: .unavailable,
                freshnessHours: nil,
                providerUsed: "snapshot-pages",
                fallbackUsed: true,
                items: [],
                generatedAtUTC: iso8601UTCString(Date())
            )
        }

        let url = buildSnapshotPagesOutlookURL()
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            return nil
        }

        let payload = try decoder.decode(PagesAreaSnapshotPayload.self, from: data)
        let sortedSnapshots = payload.snapshots.sorted {
            parseISODate($0.timeUTC) ?? .distantPast < parseISODate($1.timeUTC) ?? .distantPast
        }
        let maxHours = max(24, min(5, days) * 24)
        let horizonSnapshots = Array(sortedSnapshots.prefix(maxHours))

        var items: [FavoriteRecommendationItem] = []
        for cafeID in cafeIds {
            let requestedOsmID = parseOsmID(from: cafeID)
            var cafeName = cafeID
            let hourly = horizonSnapshots.compactMap { snapshot -> SunOutlookHourlyPoint? in
                guard let row = matchSnapshotCafe(snapshot.cafes, cafeId: cafeID, requestedOsmID: requestedOsmID) else {
                    return nil
                }
                if let rowName = row.name, !rowName.isEmpty {
                    cafeName = rowName
                }
                let cloud = row.cloudCoverPct ?? snapshot.cloudCoverPct
                let condition = canonicalCondition(
                    rawCondition: nil,
                    score: row.sunnyScore,
                    cloudCoverPct: cloud,
                    sunElevationDeg: row.sunElevationDeg
                )
                let hoursAhead = max(
                    0.0,
                    ((parseISODate(snapshot.timeUTC) ?? Date()).timeIntervalSince(Date())) / 3600.0
                )
                return SunOutlookHourlyPoint(
                    timeUTC: snapshot.timeUTC,
                    timeLocal: snapshot.timeLocal,
                    timezone: "Europe/Copenhagen",
                    condition: condition,
                    score: row.sunnyScore,
                    confidenceHint: confidenceHint(hoursAhead: hoursAhead),
                    cloudCoverPct: cloud
                )
            }

            guard !hourly.isEmpty else { continue }
            let windows = mergeHourlyIntoWindows(hourly, minDuration: prefs.minDurationMin)
            for window in windows {
                items.append(
                    buildRecommendationItem(
                        cafeID: cafeID,
                        cafeName: cafeName,
                        window: window,
                        preferredPeriods: prefs.preferredPeriods
                    )
                )
            }
        }

        items.sort {
            if $0.score == $1.score {
                return $0.startUTC < $1.startUTC
            }
            return $0.score > $1.score
        }

        let generatedDate = payload.generatedAtUTC.flatMap(parseISODate)
        let ageHours = generatedDate.map { max(0.0, Date().timeIntervalSince($0) / 3600.0) }
        let status: RecommendationDataStatus = (ageHours ?? 0.0) <= freshTTLHours ? .fresh : .stale

        return FavoritesRecommendationResponse(
            cityID: cityId,
            timezone: "Europe/Copenhagen",
            dataStatus: status,
            freshnessHours: ageHours,
            providerUsed: "snapshot-pages",
            fallbackUsed: true,
            items: Array(items.prefix(20)),
            generatedAtUTC: payload.generatedAtUTC ?? iso8601UTCString(Date())
        )
    }

    private func buildRecommendationItem(
        cafeID: String,
        cafeName: String,
        window: SunOutlookWindow,
        preferredPeriods: [String]
    ) -> FavoriteRecommendationItem {
        let durationWeight = min(55.0, Double(window.durationMin) / 10.0)
        let conditionWeight = window.condition.lowercased() == "sunny" ? 30.0 : 18.0
        let startDate = parseISODate(window.startUTC) ?? Date()
        let hoursAhead = max(0.0, startDate.timeIntervalSince(Date()) / 3600.0)
        let soonnessWeight = max(0.0, 20.0 - (hoursAhead * 1.6))
        let period = periodName(for: window.startLocal)
        let preferred = Set(preferredPeriods.map { $0.lowercased() })
        let preferredBonus = preferred.contains(period) ? 12.0 : 0.0
        let score = min(100.0, max(0.0, durationWeight + conditionWeight + soonnessWeight + preferredBonus))

        let reason: String
        if preferred.contains(period) {
            reason = "Long \(window.condition) window in your preferred \(period) period."
        } else {
            reason = "Best upcoming \(window.condition) window for this favorite."
        }

        return FavoriteRecommendationItem(
            cafeID: cafeID,
            cafeName: cafeName,
            startUTC: window.startUTC,
            endUTC: window.endUTC,
            startLocal: window.startLocal,
            endLocal: window.endLocal,
            durationMin: window.durationMin,
            condition: window.condition,
            score: score,
            reason: reason
        )
    }

    private func periodName(for localISOTime: String) -> String {
        guard let date = parseISODate(localISOTime) else { return "anytime" }
        let hour = Calendar(identifier: .gregorian).component(.hour, from: date)
        switch hour {
        case 5 ..< 11: return "morning"
        case 11 ..< 14: return "lunch"
        case 14 ..< 18: return "afternoon"
        case 18 ..< 23: return "evening"
        default: return "night"
        }
    }

    private struct PagesMatchedPoint {
        let snapshot: PagesAreaSnapshot
        let cafe: PagesCafeRow
    }

    private func parseOsmID(from cafeId: String) -> Int? {
        guard cafeId.hasPrefix("osm-") else { return nil }
        return Int(cafeId.replacingOccurrences(of: "osm-", with: ""))
    }

    private func matchSnapshotCafe(_ cafes: [PagesCafeRow], cafeId: String, requestedOsmID: Int?) -> PagesCafeRow? {
        if let requestedOsmID {
            return cafes.first { $0.osmID == requestedOsmID }
        }
        return cafes.first { row in
            let normalizedRow = "osm-\(row.osmID ?? -1)"
            return normalizedRow == cafeId
        }
    }

    private func normalizeHourlyPoints(_ hourly: [SunOutlookHourlyPoint]) -> [SunOutlookHourlyPoint] {
        hourly.map { point in
            let normalizedCondition = canonicalCondition(
                rawCondition: point.condition,
                score: point.score,
                cloudCoverPct: point.cloudCoverPct,
                sunElevationDeg: nil
            )
            guard normalizedCondition != point.condition else { return point }
            return SunOutlookHourlyPoint(
                timeUTC: point.timeUTC,
                timeLocal: point.timeLocal,
                timezone: point.timezone,
                condition: normalizedCondition,
                score: point.score,
                confidenceHint: point.confidenceHint,
                cloudCoverPct: point.cloudCoverPct
            )
        }
    }

    private func canonicalCondition(
        rawCondition: String?,
        score: Double,
        cloudCoverPct: Double?,
        sunElevationDeg: Double?
    ) -> String {
        if let sunElevationDeg, sunElevationDeg <= 0 {
            return "shaded"
        }

        let normalizedCloud = cloudCoverPct.map { max(0.0, min(100.0, $0)) }
        if let normalizedCloud, normalizedCloud >= EffectiveCondition.heavyCloudOverrideThreshold {
            return "shaded"
        }

        if score >= 55.0 {
            return "sunny"
        }
        if score >= 20.0 {
            return "partial"
        }

        let normalizedRaw = rawCondition?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if normalizedRaw == "sunny",
           (normalizedCloud ?? 0.0) < 75.0 {
            return "sunny"
        }
        if normalizedRaw == "partial" {
            return "partial"
        }

        return "shaded"
    }

    private func confidenceHint(hoursAhead: Double) -> Double {
        if hoursAhead <= 24 { return 0.9 }
        if hoursAhead <= 48 { return 0.8 }
        if hoursAhead <= 72 { return 0.72 }
        if hoursAhead <= 96 { return 0.65 }
        if hoursAhead <= 120 { return 0.58 }
        return 0.5
    }

    private struct PagesAreaSnapshotPayload: Codable {
        let generatedAtUTC: String?
        let snapshots: [PagesAreaSnapshot]

        enum CodingKeys: String, CodingKey {
            case generatedAtUTC = "generated_at_utc"
            case snapshots
        }
    }

    private struct PagesAreaSnapshot: Codable {
        let timeUTC: String
        let timeLocal: String
        let cloudCoverPct: Double
        let cafes: [PagesCafeRow]

        enum CodingKeys: String, CodingKey {
            case timeUTC = "time_utc"
            case timeLocal = "time_local"
            case cloudCoverPct = "cloud_cover_pct"
            case cafes
        }
    }

    private struct PagesCafeRow: Codable {
        let osmID: Int?
        let name: String?
        let sunnyScore: Double
        let sunnyFraction: Double
        let sunElevationDeg: Double
        let cloudCoverPct: Double?

        enum CodingKeys: String, CodingKey {
            case osmID = "osm_id"
            case name
            case sunnyScore = "sunny_score"
            case sunnyFraction = "sunny_fraction"
            case sunElevationDeg = "sun_elevation_deg"
            case cloudCoverPct = "cloud_cover_pct"
        }
    }
}
