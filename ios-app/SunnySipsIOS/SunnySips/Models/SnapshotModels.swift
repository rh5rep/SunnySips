import Foundation
import CoreLocation

struct SnapshotIndex: Codable {
    let generatedAtUTC: String
    let areas: [SnapshotAreaRef]

    enum CodingKeys: String, CodingKey {
        case generatedAtUTC = "generated_at_utc"
        case areas
    }
}

struct SnapshotAreaRef: Codable, Hashable, Identifiable {
    let area: String
    let file: String
    let count: Int

    var id: String { area }
}

struct AreaSnapshotFile: Codable {
    let generatedAtUTC: String
    let area: String
    let bbox: [Double]
    let snapshots: [TimeSnapshot]

    enum CodingKeys: String, CodingKey {
        case generatedAtUTC = "generated_at_utc"
        case area
        case bbox
        case snapshots
    }
}

struct TimeSnapshot: Codable, Hashable, Identifiable {
    let timeUTC: String
    let timeLocal: String
    let cloudCoverPct: Double
    let summary: SnapshotSummary
    let cafes: [CafeSnapshot]

    enum CodingKeys: String, CodingKey {
        case timeUTC = "time_utc"
        case timeLocal = "time_local"
        case cloudCoverPct = "cloud_cover_pct"
        case summary
        case cafes
    }

    var id: String { timeUTC }

    var localDate: Date? {
        ISO8601DateFormatter.withFractionalSeconds.date(from: timeLocal) ??
            ISO8601DateFormatter.internetDateTime.date(from: timeLocal) ??
            ISO8601DateFormatter.withFractionalSeconds.date(from: timeUTC) ??
            ISO8601DateFormatter.internetDateTime.date(from: timeUTC)
    }

    var localTimeLabel: String {
        guard let localDate else {
            return timeLocal
        }
        return DateFormatter.localTime.string(from: localDate)
    }
}

struct SnapshotSummary: Codable, Hashable {
    let total: Int
    let sunny: Int
    let partial: Int
    let shaded: Int
    let avgScore: Double

    enum CodingKeys: String, CodingKey {
        case total
        case sunny
        case partial
        case shaded
        case avgScore = "avg_score"
    }
}

struct CafeSnapshot: Codable, Hashable, Identifiable {
    let osmID: Int?
    let name: String
    let lon: Double
    let lat: Double
    let sunnyScore: Double
    let sunnyFraction: Double
    let inShadow: Bool
    let sunElevationDeg: Double
    let sunAzimuthDeg: Double
    let cloudCoverPct: Double?
    let bucket: String?

    enum CodingKeys: String, CodingKey {
        case osmID = "osm_id"
        case name
        case lon
        case lat
        case sunnyScore = "sunny_score"
        case sunnyFraction = "sunny_fraction"
        case inShadow = "in_shadow"
        case sunElevationDeg = "sun_elevation_deg"
        case sunAzimuthDeg = "sun_azimuth_deg"
        case cloudCoverPct = "cloud_cover_pct"
        case bucket
    }

    var id: String {
        if let osmID {
            return "osm-\(osmID)"
        }
        return "\(name)-\(lat)-\(lon)"
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var resolvedBucket: String {
        if let bucket {
            return bucket
        }
        if sunnyFraction >= 0.99 { return "sunny" }
        if sunnyFraction <= 0.01 { return "shaded" }
        return "partial"
    }
}

extension ISO8601DateFormatter {
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let internetDateTime: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

extension DateFormatter {
    static let localTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}
