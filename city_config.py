"""City configuration and provider routing defaults for SunnySips."""

from __future__ import annotations

from dataclasses import dataclass
from zoneinfo import ZoneInfo


@dataclass(frozen=True)
class CityConfig:
    city_id: str
    display_name: str
    timezone: str
    bbox: tuple[float, float, float, float]
    provider_order: tuple[str, ...]

    @property
    def tz(self) -> ZoneInfo:
        return ZoneInfo(self.timezone)

    @property
    def center(self) -> tuple[float, float]:
        min_lon, min_lat, max_lon, max_lat = self.bbox
        return ((min_lat + max_lat) / 2.0, (min_lon + max_lon) / 2.0)


CITY_CONFIGS: dict[str, CityConfig] = {
    "copenhagen": CityConfig(
        city_id="copenhagen",
        display_name="Copenhagen",
        timezone="Europe/Copenhagen",
        bbox=(12.50, 55.66, 12.64, 55.73),
        provider_order=("dmi", "met_no", "legacy_open_meteo"),
    ),
}


def get_city_config(city_id: str) -> CityConfig:
    return CITY_CONFIGS.get(city_id, CITY_CONFIGS["copenhagen"])

