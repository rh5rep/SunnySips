import Foundation
import CoreLocation
import MapKit
import SwiftUI

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

enum EffectiveCondition: String, Codable, CaseIterable {
    case sunny = "Sunny"
    case partial = "Partial"
    case shaded = "Shaded"

    static let heavyCloudOverrideThreshold: Double = 90.0

    var color: Color {
        switch self {
        case .sunny: return ThemeColor.sunnyGreen
        case .partial: return ThemeColor.partialAmber
        case .shaded: return ThemeColor.shadedRed
        }
    }

    var emoji: String {
        switch self {
        case .sunny: return "☀️"
        case .partial: return "⛅"
        case .shaded: return "☁️"
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

    var sunnyPercentString: String {
        String(format: "%.1f%%", sunnyFraction * 100.0)
    }

    var scoreString: String {
        String(format: "%.1f", sunnyScore)
    }

    var popularityScore: Double {
        // Stable pseudo-popularity so sorting is deterministic without a backend metric.
        let basis = id.unicodeScalars.reduce(into: UInt64(1469598103934665603)) { hash, scalar in
            hash ^= UInt64(scalar.value)
            hash = hash &* 1099511628211
        }
        return Double((basis % 500) + 500) / 200.0 // 2.5 ... 5.0
    }

    var bucket: SunnyBucket {
        if sunnyFraction >= 0.99 { return .sunny }
        if sunnyFraction <= 0.01 { return .shaded }
        return .partial
    }

    func sunnyScore(at time: Date, cloudCover: Double) -> Double {
        _ = time // Time is already represented by this snapshot row.
        guard sunElevationDeg > 0 else { return 0 }
        let clampedCloud = max(0.0, min(100.0, cloudCover))
        let weatherFactor = 1.0 - (clampedCloud / 100.0)
        return max(0.0, min(100.0, (100.0 * sunnyFraction * weatherFactor * 10.0).rounded() / 10.0))
    }

    func effectiveCondition(at time: Date, cloudCover: Double) -> EffectiveCondition {
        guard sunElevationDeg > 0 else { return .shaded }
        let score = sunnyScore(at: time, cloudCover: cloudCover)
        if cloudCover >= EffectiveCondition.heavyCloudOverrideThreshold { return .shaded }
        if score >= 55.0 { return .sunny }
        if score >= 20.0 { return .partial }
        return .shaded
    }

    var effectiveCondition: EffectiveCondition {
        effectiveCondition(at: Date(), cloudCover: cloudCoverPct ?? 50.0)
    }

    func applyingCloudCover(_ cloudCover: Double) -> SunnyCafe {
        let clampedCloud = max(0.0, min(100.0, cloudCover))
        let recomputedScore = sunnyScore(at: Date(), cloudCover: clampedCloud)

        return SunnyCafe(
            osmID: osmID,
            name: name,
            lon: lon,
            lat: lat,
            sunnyScore: recomputedScore,
            sunnyFraction: sunnyFraction,
            inShadow: inShadow,
            sunElevationDeg: sunElevationDeg,
            sunAzimuthDeg: sunAzimuthDeg,
            cloudCoverPct: clampedCloud
        )
    }

    func applyingNightOverride() -> SunnyCafe {
        SunnyCafe(
            osmID: osmID,
            name: name,
            lon: lon,
            lat: lat,
            sunnyScore: 0,
            sunnyFraction: 0,
            inShadow: true,
            sunElevationDeg: sunElevationDeg,
            sunAzimuthDeg: sunAzimuthDeg,
            cloudCoverPct: cloudCoverPct
        )
    }
}

struct SunlightWindow: Equatable {
    let sunrise: Date
    let sunset: Date

    func contains(_ date: Date) -> Bool {
        date >= sunrise && date <= sunset
    }
}

enum SunlightCalculator {
    private static let zenith = 90.833

    static func daylightWindow(
        on date: Date,
        coordinate: CLLocationCoordinate2D,
        timeZone: TimeZone = TimeZone(identifier: "Europe/Copenhagen") ?? .current
    ) -> SunlightWindow? {
        guard let sunrise = solarEventTime(.sunrise, on: date, coordinate: coordinate, timeZone: timeZone),
              let sunset = solarEventTime(.sunset, on: date, coordinate: coordinate, timeZone: timeZone)
        else {
            return nil
        }
        return SunlightWindow(
            sunrise: min(sunrise, sunset),
            sunset: max(sunrise, sunset)
        )
    }

    private enum SolarEvent {
        case sunrise
        case sunset
    }

    private static func solarEventTime(
        _ event: SolarEvent,
        on date: Date,
        coordinate: CLLocationCoordinate2D,
        timeZone: TimeZone
    ) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        guard let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) else {
            return nil
        }

        let longitudeHour = coordinate.longitude / 15.0
        let baseHour = event == .sunrise ? 6.0 : 18.0
        let t = Double(dayOfYear) + ((baseHour - longitudeHour) / 24.0)

        let meanAnomaly = (0.9856 * t) - 3.289
        var trueLongitude = meanAnomaly
        trueLongitude += 1.916 * sin(deg2rad(meanAnomaly))
        trueLongitude += 0.020 * sin(deg2rad(2 * meanAnomaly))
        trueLongitude += 282.634
        trueLongitude = normalizeDegrees(trueLongitude)

        var rightAscension = rad2deg(atan(0.91764 * tan(deg2rad(trueLongitude))))
        rightAscension = normalizeDegrees(rightAscension)

        let lQuadrant = floor(trueLongitude / 90.0) * 90.0
        let raQuadrant = floor(rightAscension / 90.0) * 90.0
        rightAscension += (lQuadrant - raQuadrant)
        rightAscension /= 15.0

        let sinDeclination = 0.39782 * sin(deg2rad(trueLongitude))
        let cosDeclination = cos(asin(sinDeclination))

        let cosHourAngle = (
            cos(deg2rad(zenith)) - (sinDeclination * sin(deg2rad(coordinate.latitude)))
        ) / (cosDeclination * cos(deg2rad(coordinate.latitude)))

        if cosHourAngle > 1.0 || cosHourAngle < -1.0 {
            return nil
        }

        var hourAngle = event == .sunrise
            ? (360.0 - rad2deg(acos(cosHourAngle)))
            : rad2deg(acos(cosHourAngle))
        hourAngle /= 15.0

        let localMeanTime = hourAngle + rightAscension - (0.06571 * t) - 6.622
        let utcHours = normalizeHours(localMeanTime - longitudeHour)
        let timeZoneOffsetHours = Double(timeZone.secondsFromGMT(for: date)) / 3600.0
        var localHours = utcHours + timeZoneOffsetHours
        var dayOffset = 0

        while localHours < 0 {
            localHours += 24
            dayOffset -= 1
        }
        while localHours >= 24 {
            localHours -= 24
            dayOffset += 1
        }

        guard let adjustedDay = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: date)) else {
            return nil
        }
        return adjustedDay.addingTimeInterval(localHours * 3600.0)
    }

    private static func normalizeDegrees(_ value: Double) -> Double {
        var result = value.truncatingRemainder(dividingBy: 360.0)
        if result < 0 { result += 360.0 }
        return result
    }

    private static func normalizeHours(_ value: Double) -> Double {
        var result = value.truncatingRemainder(dividingBy: 24.0)
        if result < 0 { result += 24.0 }
        return result
    }

    private static func deg2rad(_ degrees: Double) -> Double {
        degrees * .pi / 180.0
    }

    private static func rad2deg(_ radians: Double) -> Double {
        radians * 180.0 / .pi
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

    var adjustedTitle: String {
        "\(title) (weather-adjusted)"
    }
}

enum SunnySortOption: String, CaseIterable, Identifiable {
    case bestScore
    case mostSunny
    case nameAZ
    case distanceFromUser
    case popularity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bestScore: return "Best Score"
        case .mostSunny: return "Most Sunny"
        case .nameAZ: return "Name A-Z"
        case .distanceFromUser: return "Distance from User"
        case .popularity: return "Popularity"
        }
    }
}

enum SunnyQuickPreset: String, CaseIterable, Identifiable {
    case bestRightNow
    case sunnyAfternoon
    case favoritesNearMe

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bestRightNow: return "Best Right Now"
        case .sunnyAfternoon: return "Sunny Afternoon"
        case .favoritesNearMe: return "Favorites Near Me"
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
    var favoritesOnly: Bool = false
}

extension Date {
    static var copenhagenCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Copenhagen") ?? .current
        return calendar
    }

    static var predictionRange24h: ClosedRange<Date> {
        let now = Date().roundedDownToQuarterHour()
        let end = now.addingTimeInterval(24 * 60 * 60)
        return now ... end
    }

    func roundedToQuarterHour() -> Date {
        let interval: TimeInterval = 15 * 60
        let rounded = (timeIntervalSince1970 / interval).rounded() * interval
        return Date(timeIntervalSince1970: rounded)
    }

    func roundedDownToQuarterHour() -> Date {
        let interval: TimeInterval = 15 * 60
        let roundedDown = floor(timeIntervalSince1970 / interval) * interval
        return Date(timeIntervalSince1970: roundedDown)
    }

    func clampedToPredictionWindow() -> Date {
        let range = Date.predictionRange24h
        if self < range.lowerBound { return range.lowerBound.roundedDownToQuarterHour() }
        if self > range.upperBound { return range.upperBound.roundedDownToQuarterHour() }
        return roundedDownToQuarterHour()
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

extension SunnyCafe {
    func distanceMeters(from location: CLLocationCoordinate2D?) -> CLLocationDistance? {
        guard let location else { return nil }
        let current = CLLocation(latitude: location.latitude, longitude: location.longitude)
        let target = CLLocation(latitude: lat, longitude: lon)
        return current.distance(from: target)
    }

    func matchesFuzzy(_ rawQuery: String) -> Bool {
        let query = rawQuery.normalizedForSearch
        guard !query.isEmpty else { return true }
        let value = name.normalizedForSearch

        if value.contains(query) {
            return true
        }

        let valueTokens = value.split(separator: " ")
        if valueTokens.contains(where: { $0.contains(query) }) {
            return true
        }

        // Light fuzzy matching to catch typos such as "esspreso".
        if query.count >= 3 {
            if value.levenshteinDistance(to: query) <= 2 {
                return true
            }
            if valueTokens.contains(where: { String($0).levenshteinDistance(to: query) <= 1 }) {
                return true
            }
        }

        return false
    }
}

extension String {
    var normalizedForSearch: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[^a-z0-9 ]", with: "", options: .regularExpression)
    }

    func levenshteinDistance(to other: String) -> Int {
        let a = Array(self)
        let b = Array(other)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }

        var distances = Array(0 ... b.count)
        for (i, ca) in a.enumerated() {
            var previous = distances[0]
            distances[0] = i + 1
            for (j, cb) in b.enumerated() {
                let temp = distances[j + 1]
                if ca == cb {
                    distances[j + 1] = previous
                } else {
                    distances[j + 1] = Swift.min(previous, distances[j], temp) + 1
                }
                previous = temp
            }
        }
        return distances[b.count]
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
