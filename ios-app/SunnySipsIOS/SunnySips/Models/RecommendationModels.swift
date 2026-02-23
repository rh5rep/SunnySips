import Foundation

enum RecommendationDataStatus: String, Codable {
    case fresh
    case stale
    case unavailable
}

struct SunOutlookHourlyPoint: Codable, Hashable, Identifiable {
    let timeUTC: String
    let timeLocal: String
    let timezone: String?
    let condition: String
    let score: Double
    let confidenceHint: Double
    let cloudCoverPct: Double?

    enum CodingKeys: String, CodingKey {
        case timeUTC = "time_utc"
        case timeLocal = "time_local"
        case timezone
        case condition
        case score
        case confidenceHint = "confidence_hint"
        case cloudCoverPct = "cloud_cover_pct"
    }

    var id: String { timeUTC }
}

struct SunOutlookWindow: Codable, Hashable, Identifiable {
    let startUTC: String
    let endUTC: String
    let startLocal: String
    let endLocal: String
    let durationMin: Int
    let condition: String

    enum CodingKeys: String, CodingKey {
        case startUTC = "start_utc"
        case endUTC = "end_utc"
        case startLocal = "start_local"
        case endLocal = "end_local"
        case durationMin = "duration_min"
        case condition
    }

    var id: String { "\(startUTC)-\(endUTC)" }
}

struct CafeSunOutlookResponse: Codable {
    let cafeID: String
    let cityID: String
    let timezone: String
    let dataStatus: RecommendationDataStatus
    let freshnessHours: Double?
    let providerUsed: String?
    let fallbackUsed: Bool
    let hourly: [SunOutlookHourlyPoint]
    let windows: [SunOutlookWindow]
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

struct FavoriteRecommendationItem: Codable, Hashable, Identifiable {
    let cafeID: String
    let cafeName: String
    let startUTC: String
    let endUTC: String
    let startLocal: String
    let endLocal: String
    let durationMin: Int
    let condition: String
    let score: Double
    let reason: String

    enum CodingKeys: String, CodingKey {
        case cafeID = "cafe_id"
        case cafeName = "cafe_name"
        case startUTC = "start_utc"
        case endUTC = "end_utc"
        case startLocal = "start_local"
        case endLocal = "end_local"
        case durationMin = "duration_min"
        case condition
        case score
        case reason
    }

    var id: String { "\(cafeID)-\(startUTC)-\(endUTC)" }
}

struct FavoritesRecommendationResponse: Codable {
    let cityID: String
    let timezone: String
    let dataStatus: RecommendationDataStatus
    let freshnessHours: Double?
    let providerUsed: String?
    let fallbackUsed: Bool
    let items: [FavoriteRecommendationItem]
    let generatedAtUTC: String?

    enum CodingKeys: String, CodingKey {
        case cityID = "city_id"
        case timezone
        case dataStatus = "data_status"
        case freshnessHours = "freshness_hours"
        case providerUsed = "provider_used"
        case fallbackUsed = "fallback_used"
        case items
        case generatedAtUTC = "generated_at_utc"
    }
}

struct RecommendationPrefsPayload: Codable {
    let minDurationMin: Int
    let preferredPeriods: [String]

    enum CodingKeys: String, CodingKey {
        case minDurationMin = "min_duration_min"
        case preferredPeriods = "preferred_periods"
    }
}

struct FavoritesRecommendationRequestPayload: Codable {
    let cityID: String
    let favoriteIDs: [String]
    let days: Int
    let prefs: RecommendationPrefsPayload

    enum CodingKeys: String, CodingKey {
        case cityID = "city_id"
        case favoriteIDs = "favorite_ids"
        case days
        case prefs
    }
}

struct CityDescriptor: Codable, Hashable, Identifiable {
    let cityID: String
    let displayName: String
    let timezone: String
    let bbox: [Double]

    enum CodingKeys: String, CodingKey {
        case cityID = "city_id"
        case displayName = "display_name"
        case timezone
        case bbox
    }

    var id: String { cityID }
}

struct CityListResponse: Codable {
    let cities: [CityDescriptor]
}

