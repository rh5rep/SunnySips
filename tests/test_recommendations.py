import unittest

from recommendations import cache_status_from_age, merge_windows, rank_recommendations


class RecommendationLogicTests(unittest.TestCase):
    def test_merge_windows_filters_short_blips(self):
        hourly = [
            {"time_utc": "2026-02-21T10:00:00+00:00", "time_local": "2026-02-21T11:00:00+01:00", "timezone": "Europe/Copenhagen", "condition": "partial"},
            {"time_utc": "2026-02-21T11:00:00+00:00", "time_local": "2026-02-21T12:00:00+01:00", "timezone": "Europe/Copenhagen", "condition": "sunny"},
            {"time_utc": "2026-02-21T12:00:00+00:00", "time_local": "2026-02-21T13:00:00+01:00", "timezone": "Europe/Copenhagen", "condition": "shaded"},
            {"time_utc": "2026-02-21T13:00:00+00:00", "time_local": "2026-02-21T14:00:00+01:00", "timezone": "Europe/Copenhagen", "condition": "sunny"},
        ]
        windows = merge_windows(hourly, min_duration_min=90)
        self.assertEqual(len(windows), 1)
        self.assertEqual(windows[0]["duration_min"], 120)
        self.assertEqual(windows[0]["condition"], "partial")

    def test_rank_recommendations_is_deterministic(self):
        windows_by_cafe = {
            "osm-1": {
                "cafe_name": "Alpha",
                "windows": [
                    {
                        "start_utc": "2030-02-21T10:00:00+00:00",
                        "end_utc": "2030-02-21T12:00:00+00:00",
                        "start_local": "2030-02-21T11:00:00+01:00",
                        "end_local": "2030-02-21T13:00:00+01:00",
                        "duration_min": 120,
                        "condition": "sunny",
                    }
                ],
            },
            "osm-2": {
                "cafe_name": "Beta",
                "windows": [
                    {
                        "start_utc": "2030-02-21T10:00:00+00:00",
                        "end_utc": "2030-02-21T11:00:00+00:00",
                        "start_local": "2030-02-21T11:00:00+01:00",
                        "end_local": "2030-02-21T12:00:00+01:00",
                        "duration_min": 60,
                        "condition": "partial",
                    }
                ],
            },
        }
        ranked = rank_recommendations(windows_by_cafe, ["lunch"])
        self.assertEqual(ranked[0]["cafe_id"], "osm-1")
        self.assertGreater(ranked[0]["score"], ranked[1]["score"])

    def test_cache_status(self):
        self.assertEqual(cache_status_from_age(0.5), "fresh")
        self.assertEqual(cache_status_from_age(3.0), "stale")
        self.assertEqual(cache_status_from_age(13.0), "unavailable")
        self.assertEqual(cache_status_from_age(None), "unavailable")


if __name__ == "__main__":
    unittest.main()

