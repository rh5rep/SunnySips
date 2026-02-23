"""Weather provider router with disk cache and stale/fallback metadata."""

from __future__ import annotations

import json
import math
import pathlib
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Callable

import requests

from city_config import get_city_config
from weather import get_cloud_cover as get_legacy_cloud_cover


UTC = timezone.utc
CACHE_ROOT = pathlib.Path(".cache/sunnysips_v1/weather")
FRESH_TTL_HOURS = 2.0
STALE_TTL_HOURS = 12.0

MET_NO_URL = "https://api.met.no/weatherapi/locationforecast/2.0/compact"
DMI_EDR_URL = "https://dmigw.govcloud.dk/v1/forecastedr/collections/harmonie_dini_sf/position"


@dataclass
class WeatherSeriesResult:
    provider_used: str
    fallback_used: bool
    data_status: str  # fresh | stale | unavailable
    freshness_hours: float | None
    fetched_at: datetime
    cloud_by_hour: dict[datetime, float]


def get_cloud_cover_series(
    city_id: str,
    start_utc: datetime,
    end_utc: datetime,
) -> WeatherSeriesResult:
    city = get_city_config(city_id)
    start_utc = _ensure_utc(start_utc).replace(minute=0, second=0, microsecond=0)
    end_utc = _ensure_utc(end_utc).replace(minute=0, second=0, microsecond=0)
    fallback_used = False

    fetchers: dict[str, Callable[[str, datetime, datetime], WeatherSeriesResult]] = {
        "dmi": _fetch_dmi_series,
        "met_no": _fetch_met_no_series,
        "legacy_open_meteo": _fetch_legacy_series,
    }

    last_error: Exception | None = None
    provider_errors: dict[str, str] = {}
    for index, provider in enumerate(city.provider_order):
        fetcher = fetchers.get(provider)
        if fetcher is None:
            continue
        try:
            result = fetcher(city.city_id, start_utc, end_utc)
            result.fallback_used = fallback_used or index > 0
            return result
        except Exception as exc:  # noqa: BLE001 - continue to next provider
            last_error = exc
            provider_errors[provider] = f"{type(exc).__name__}: {exc}"
            fallback_used = True
            continue

    if last_error:
        raise RuntimeError(f"All providers failed: {provider_errors}") from last_error
    raise RuntimeError("No weather providers configured")


def _fetch_dmi_series(city_id: str, start_utc: datetime, end_utc: datetime) -> WeatherSeriesResult:
    cache_key = _cache_key(city_id, "dmi", start_utc, end_utc)
    cached = _load_cache(cache_key)
    if cached and cached["age_hours"] <= FRESH_TTL_HOURS:
        return _as_series_result("dmi", cached["series"], cached["fetched_at"], "fresh", cached["age_hours"])

    try:
        city = get_city_config(city_id)
        lat, lon = city.center
        params = {
            "coords": f"POINT({lon} {lat})",
            "datetime": f"{start_utc.isoformat()}/{end_utc.isoformat()}",
            "parameter-name": "cloud_cover",
        }
        response = requests.get(DMI_EDR_URL, params=params, timeout=20)
        response.raise_for_status()
        payload = response.json()
        series = _parse_dmi_payload(payload, start_utc, end_utc)
        fetched_at = datetime.now(UTC)
        _save_cache(cache_key, fetched_at, series)
        return _as_series_result("dmi", series, fetched_at, "fresh", 0.0)
    except Exception:
        if cached and cached["age_hours"] <= STALE_TTL_HOURS:
            return _as_series_result("dmi", cached["series"], cached["fetched_at"], "stale", cached["age_hours"])
        raise


def _fetch_met_no_series(city_id: str, start_utc: datetime, end_utc: datetime) -> WeatherSeriesResult:
    cache_key = _cache_key(city_id, "met_no", start_utc, end_utc)
    cached = _load_cache(cache_key)
    if cached and cached["age_hours"] <= FRESH_TTL_HOURS:
        return _as_series_result("met_no", cached["series"], cached["fetched_at"], "fresh", cached["age_hours"])

    try:
        city = get_city_config(city_id)
        lat, lon = city.center
        response = requests.get(
            MET_NO_URL,
            params={"lat": f"{lat:.6f}", "lon": f"{lon:.6f}"},
            headers={"User-Agent": "SunnySips/1.0 (api)"},
            timeout=20,
        )
        response.raise_for_status()
        payload = response.json()
        series = _parse_met_no_payload(payload, start_utc, end_utc)
        fetched_at = datetime.now(UTC)
        _save_cache(cache_key, fetched_at, series)
        return _as_series_result("met_no", series, fetched_at, "fresh", 0.0)
    except Exception:
        if cached and cached["age_hours"] <= STALE_TTL_HOURS:
            return _as_series_result("met_no", cached["series"], cached["fetched_at"], "stale", cached["age_hours"])
        raise


def _fetch_legacy_series(city_id: str, start_utc: datetime, end_utc: datetime) -> WeatherSeriesResult:
    cache_key = _cache_key(city_id, "legacy_open_meteo", start_utc, end_utc)
    cached = _load_cache(cache_key)
    if cached and cached["age_hours"] <= FRESH_TTL_HOURS:
        return _as_series_result(
            "legacy_open_meteo",
            cached["series"],
            cached["fetched_at"],
            "fresh",
            cached["age_hours"],
        )

    try:
        dt = start_utc
        series: dict[str, float] = {}
        while dt <= end_utc:
            series[dt.isoformat()] = float(get_legacy_cloud_cover(dt))
            dt += timedelta(hours=1)
        fetched_at = datetime.now(UTC)
        _save_cache(cache_key, fetched_at, series)
        return _as_series_result("legacy_open_meteo", series, fetched_at, "fresh", 0.0)
    except Exception:
        if cached and cached["age_hours"] <= STALE_TTL_HOURS:
            return _as_series_result(
                "legacy_open_meteo",
                cached["series"],
                cached["fetched_at"],
                "stale",
                cached["age_hours"],
            )
        raise


def _parse_dmi_payload(payload: dict, start_utc: datetime, end_utc: datetime) -> dict[str, float]:
    # DMI EDR responses can vary by collection; parse defensively and normalize hourly.
    candidates: dict[datetime, float] = {}

    ranges = payload.get("ranges", {})
    if isinstance(ranges, dict):
        cloud_node = ranges.get("cloud_cover")
        if isinstance(cloud_node, dict):
            values = cloud_node.get("values", [])
            axis_values = payload.get("domain", {}).get("axes", {}).get("t", {}).get("values", [])
            for raw_t, raw_c in zip(axis_values, values):
                dt = _parse_iso(raw_t)
                if dt is None or raw_c is None:
                    continue
                candidates[dt] = float(raw_c)

    if not candidates:
        features = payload.get("features", [])
        for feature in features if isinstance(features, list) else []:
            properties = feature.get("properties", {})
            parameters = properties.get("parameters", {})
            cloud = parameters.get("cloud_cover")
            if cloud is None:
                cloud = parameters.get("cloud_area_fraction")
            dt = _parse_iso(properties.get("datetime") or properties.get("time"))
            if dt is None or cloud is None:
                continue
            if isinstance(cloud, dict):
                cloud = cloud.get("value")
            if cloud is None:
                continue
            candidates[dt] = float(cloud)

    if not candidates:
        raise RuntimeError("DMI payload did not include cloud cover timeseries")

    return _normalize_hourly_candidates(candidates, start_utc, end_utc)


def _parse_met_no_payload(payload: dict, start_utc: datetime, end_utc: datetime) -> dict[str, float]:
    candidates: dict[datetime, float] = {}
    timeseries = payload.get("properties", {}).get("timeseries", [])
    for point in timeseries if isinstance(timeseries, list) else []:
        dt = _parse_iso(point.get("time"))
        if dt is None:
            continue
        cloud = (
            point.get("data", {})
            .get("instant", {})
            .get("details", {})
            .get("cloud_area_fraction")
        )
        if cloud is None:
            continue
        candidates[dt] = float(cloud)

    if not candidates:
        raise RuntimeError("MET payload did not include cloud_area_fraction values")

    return _normalize_hourly_candidates(candidates, start_utc, end_utc)


def _normalize_hourly_candidates(
    candidates: dict[datetime, float],
    start_utc: datetime,
    end_utc: datetime,
) -> dict[str, float]:
    ordered = sorted(candidates.items(), key=lambda x: x[0])
    if not ordered:
        raise RuntimeError("No weather candidates to normalize")

    out: dict[str, float] = {}
    dt = start_utc
    while dt <= end_utc:
        nearest_dt, nearest_cloud = min(
            ordered,
            key=lambda item: abs(item[0].timestamp() - dt.timestamp()),
        )
        # Guard against extreme extrapolation if provider does not cover full requested horizon.
        if abs((nearest_dt - dt).total_seconds()) > 12 * 3600:
            raise RuntimeError("Provider coverage too far from requested horizon")
        out[dt.isoformat()] = max(0.0, min(100.0, float(nearest_cloud)))
        dt += timedelta(hours=1)
    return out


def _as_series_result(
    provider: str,
    serialized_series: dict[str, float],
    fetched_at: datetime,
    data_status: str,
    freshness_hours: float | None,
) -> WeatherSeriesResult:
    cloud_by_hour: dict[datetime, float] = {}
    for raw_dt, cloud in serialized_series.items():
        dt = _parse_iso(raw_dt)
        if dt is None:
            continue
        cloud_by_hour[dt] = max(0.0, min(100.0, float(cloud)))

    return WeatherSeriesResult(
        provider_used=provider,
        fallback_used=False,
        data_status=data_status,
        freshness_hours=freshness_hours,
        fetched_at=fetched_at,
        cloud_by_hour=cloud_by_hour,
    )


def _cache_key(city_id: str, provider: str, start_utc: datetime, end_utc: datetime) -> str:
    return f"{city_id}-{provider}-{start_utc.date().isoformat()}-{end_utc.date().isoformat()}"


def _cache_file(key: str) -> pathlib.Path:
    CACHE_ROOT.mkdir(parents=True, exist_ok=True)
    return CACHE_ROOT / f"{key}.json"


def _save_cache(key: str, fetched_at: datetime, series: dict[str, float]) -> None:
    payload = {
        "fetched_at": fetched_at.isoformat(),
        "series": series,
    }
    _cache_file(key).write_text(json.dumps(payload), encoding="utf-8")


def _load_cache(key: str) -> dict | None:
    path = _cache_file(key)
    if not path.exists():
        return None
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
        fetched_at = _parse_iso(payload.get("fetched_at"))
        if fetched_at is None:
            return None
        age_hours = (datetime.now(UTC) - fetched_at).total_seconds() / 3600.0
        if age_hours > STALE_TTL_HOURS:
            return None
        return {
            "fetched_at": fetched_at,
            "age_hours": age_hours,
            "series": payload.get("series", {}),
        }
    except Exception:
        return None


def _parse_iso(raw: str | None) -> datetime | None:
    if not raw:
        return None
    try:
        parsed = datetime.fromisoformat(raw.replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=UTC)
        return parsed.astimezone(UTC)
    except Exception:
        return None


def _ensure_utc(dt: datetime) -> datetime:
    if dt.tzinfo is None:
        return dt.replace(tzinfo=UTC)
    return dt.astimezone(UTC)


def confidence_hint(hours_ahead: float) -> float:
    # Heuristic confidence indicator (not probabilistic uncertainty).
    if hours_ahead <= 24:
        return 0.9
    if hours_ahead <= 48:
        return 0.8
    if hours_ahead <= 72:
        return 0.72
    if hours_ahead <= 96:
        return 0.65
    if hours_ahead <= 120:
        return 0.58
    return 0.5


def round_hours_since(dt: datetime, now: datetime | None = None) -> float:
    now = _ensure_utc(now or datetime.now(UTC))
    return max(0.0, round((now - _ensure_utc(dt)).total_seconds() / 3600.0, 2))


def hours_until(target: datetime, now: datetime | None = None) -> float:
    now = _ensure_utc(now or datetime.now(UTC))
    return max(0.0, (target - now).total_seconds() / 3600.0)
