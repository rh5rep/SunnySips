import Foundation
import CoreLocation
import MapKit

struct SunnyResponse: Codable {
    let time: Date
    let cloudCoverPct: Double
    let count: Int
    let cafes: [SunnyCafe]

    enum CodingKeys: String, CodingKey {
        case time
        case cloudCoverPct = "cloud_cover_pct"
        case count
        case cafes
    }
}

struct SunnyCafe: Codable, Identifiable, Hashable {
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

    var sunnyPercent: Int {
        Int((sunnyFraction * 100).rounded())
    }

    var bucket: SunnyBucket {
        if sunnyFraction >= 0.99 { return .sunny }
        if sunnyFraction <= 0.01 { return .shaded }
        return .partial
    }
}

enum SunnyBucket: String, CaseIterable, Identifiable {
    case sunny
    case partial
    case shaded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sunny: return "Sunny"
        case .partial: return "Partial"
        case .shaded: return "Shaded"
        }
    }

    var filterValue: SunnyBucketFilter {
        switch self {
        case .sunny: return .sunny
        case .partial: return .partial
        case .shaded: return .shaded
        }
    }
}

enum SunnyBucketFilter: String, CaseIterable, Identifiable, Hashable {
    case sunny
    case partial
    case shaded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sunny: return "Sunny"
        case .partial: return "Partial"
        case .shaded: return "Shaded"
        }
    }
}

enum SunnySortOption: String, CaseIterable, Identifiable {
    case bestScore
    case mostSunny
    case nameAZ

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bestScore: return "Best Score"
        case .mostSunny: return "Most Sunny"
        case .nameAZ: return "Name A-Z"
        }
    }
}

struct BoundingBox: Equatable {
    let minLon: Double
    let minLat: Double
    let maxLon: Double
    let maxLat: Double

    var center: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: (minLat + maxLat) * 0.5,
            longitude: (minLon + maxLon) * 0.5
        )
    }

    var span: MKCoordinateSpan {
        MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.15, 0.01),
            longitudeDelta: max((maxLon - minLon) * 1.15, 0.01)
        )
    }

    var region: MKCoordinateRegion {
        MKCoordinateRegion(center: center, span: span)
    }
}

enum SunnyArea: String, CaseIterable, Identifiable {
    case coreCopenhagen = "core-cph"
    case indreBy = "indre-by"
    case norrebro = "norrebro"
    case frederiksberg = "frederiksberg"
    case osterbro = "osterbro"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .coreCopenhagen: return "Core Copenhagen"
        case .indreBy: return "Indre By"
        case .norrebro: return "Nørrebro"
        case .frederiksberg: return "Frederiksberg"
        case .osterbro: return "Østerbro"
        }
    }

    var bbox: BoundingBox {
        switch self {
        case .coreCopenhagen:
            return BoundingBox(minLon: 12.500, minLat: 55.660, maxLon: 12.640, maxLat: 55.730)
        case .indreBy:
            return BoundingBox(minLon: 12.560, minLat: 55.675, maxLon: 12.600, maxLat: 55.695)
        case .norrebro:
            return BoundingBox(minLon: 12.520, minLat: 55.680, maxLon: 12.590, maxLat: 55.720)
        case .frederiksberg:
            return BoundingBox(minLon: 12.500, minLat: 55.660, maxLon: 12.560, maxLat: 55.700)
        case .osterbro:
            return BoundingBox(minLon: 12.560, minLat: 55.690, maxLon: 12.640, maxLat: 55.730)
        }
    }
}

struct SunnyStatsSummary {
    let total: Int
    let sunny: Int
    let partial: Int
    let shaded: Int
    let averageScore: Int

    static let empty = SunnyStatsSummary(total: 0, sunny: 0, partial: 0, shaded: 0, averageScore: 0)
}

struct SunnyFilters {
    var area: SunnyArea = .coreCopenhagen
    var useNow: Bool = true
    var selectedTime: Date = Date().roundedToQuarterHour()
    var selectedBuckets: Set<SunnyBucketFilter> = [.sunny]
    var minScore: Double = 0
    var searchText: String = ""
    var sort: SunnySortOption = .bestScore
}

extension Date {
    static var copenhagenCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Copenhagen") ?? .current
        return calendar
    }

    static var todayRange: ClosedRange<Date> {
        let cal = Date.copenhagenCalendar
        let now = Date()
        let start = cal.startOfDay(for: now)
        let end = cal.date(byAdding: .day, value: 1, to: start)?.addingTimeInterval(-1) ?? now
        return start ... end
    }

    func roundedToQuarterHour() -> Date {
        let interval: TimeInterval = 15 * 60
        let rounded = (timeIntervalSince1970 / interval).rounded() * interval
        return Date(timeIntervalSince1970: rounded)
    }

    func clampedToToday() -> Date {
        let range = Date.todayRange
        if self < range.lowerBound { return range.lowerBound.roundedToQuarterHour() }
        if self > range.upperBound { return range.upperBound.roundedToQuarterHour() }
        return roundedToQuarterHour()
    }
}

extension MKCoordinateRegion {
    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let latDelta = span.latitudeDelta * 0.5
        let lonDelta = span.longitudeDelta * 0.5
        let minLat = center.latitude - latDelta
        let maxLat = center.latitude + latDelta
        let minLon = center.longitude - lonDelta
        let maxLon = center.longitude + lonDelta
        return coordinate.latitude >= minLat && coordinate.latitude <= maxLat &&
            coordinate.longitude >= minLon && coordinate.longitude <= maxLon
    }

    func approximatelyEquals(_ other: MKCoordinateRegion, tolerance: Double = 0.0005) -> Bool {
        abs(center.latitude - other.center.latitude) < tolerance &&
            abs(center.longitude - other.center.longitude) < tolerance &&
            abs(span.latitudeDelta - other.span.latitudeDelta) < tolerance &&
            abs(span.longitudeDelta - other.span.longitudeDelta) < tolerance
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
