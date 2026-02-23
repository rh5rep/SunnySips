//
//  SunnySipsTests.swift
//  SunnySipsTests
//
//  Created by Rami Hanna on 2/17/26.
//

import Testing
@testable import SunnySips

struct SunnySipsTests {

    @Test func decodeCafeSunOutlookResponse() throws {
        let json = """
        {
          "cafe_id": "osm-123",
          "city_id": "copenhagen",
          "timezone": "Europe/Copenhagen",
          "data_status": "stale",
          "freshness_hours": 3.2,
          "provider_used": "met_no",
          "fallback_used": true,
          "hourly": [],
          "windows": [
            {
              "start_utc": "2026-02-21T10:00:00+00:00",
              "end_utc": "2026-02-21T12:00:00+00:00",
              "start_local": "2026-02-21T11:00:00+01:00",
              "end_local": "2026-02-21T13:00:00+01:00",
              "duration_min": 120,
              "condition": "sunny"
            }
          ],
          "generated_at_utc": "2026-02-21T10:00:00+00:00"
        }
        """
        let data = try #require(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(CafeSunOutlookResponse.self, from: data)
        #expect(decoded.cafeID == "osm-123")
        #expect(decoded.cityID == "copenhagen")
        #expect(decoded.dataStatus == .stale)
        #expect(decoded.windows.count == 1)
        #expect(decoded.windows[0].durationMin == 120)
    }

    @Test func decodeFavoritesRecommendationResponse() throws {
        let json = """
        {
          "city_id": "copenhagen",
          "timezone": "Europe/Copenhagen",
          "data_status": "fresh",
          "freshness_hours": 0.1,
          "provider_used": "dmi",
          "fallback_used": false,
          "items": [
            {
              "cafe_id": "osm-999",
              "cafe_name": "Test Cafe",
              "start_utc": "2026-02-21T10:00:00+00:00",
              "end_utc": "2026-02-21T11:00:00+00:00",
              "start_local": "2026-02-21T11:00:00+01:00",
              "end_local": "2026-02-21T12:00:00+01:00",
              "duration_min": 60,
              "condition": "partial",
              "score": 54.5,
              "reason": "solid sun window"
            }
          ],
          "generated_at_utc": "2026-02-21T10:00:00+00:00"
        }
        """
        let data = try #require(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(FavoritesRecommendationResponse.self, from: data)
        #expect(decoded.dataStatus == .fresh)
        #expect(decoded.items.count == 1)
        #expect(decoded.items[0].cafeName == "Test Cafe")
    }

}
