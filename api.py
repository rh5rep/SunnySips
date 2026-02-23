"""FastAPI server for SunnySips."""
import json
import pathlib
from collections.abc import Iterable
from datetime import datetime, timedelta, timezone

from fastapi import FastAPI, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from city_config import CITY_CONFIGS, get_city_config
from recommendations import (
    FRESH_TTL_HOURS,
    OUTLOOK_CACHE_ROOT,
    RECOMMENDATIONS_CACHE_ROOT,
    STALE_TTL_HOURS,
    cache_key_from_parts,
    cache_status_from_age,
    classify_condition,
    merge_windows,
    rank_recommendations,
    read_cache,
    write_cache,
)
from shadow_engine import TO_UTM, build_building_index, compute_sunny_cafes
from weather import get_cloud_cover
from weather_router import confidence_hint, get_cloud_cover_series
from shapely import make_valid
from shapely.geometry import shape
from shapely.ops import transform

app = FastAPI(title="SunnySips", version="0.1.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

DATA_DIR = pathlib.Path("data")

# ---------- Load data at startup ----------

def _load_cafes() -> list[dict]:
    path = DATA_DIR / "cafes_copenhagen.geojson"
    with open(path) as f:
        return json.load(f)["features"]


def _as_float(value) -> float | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        cleaned = value.lower().replace("m", "").strip()
        try:
            return float(cleaned)
        except ValueError:
            return None
    return None


def _resolve_height_m(properties: dict) -> tuple[float, str]:
    direct_height = _as_float(properties.get("height"))
    if direct_height and direct_height > 0:
        return direct_height, "height_tag"

    # Datafordeler/BBR: number of floors for many buildings.
    bbr_levels = _as_float(properties.get("byg054AntalEtager"))
    if bbr_levels and bbr_levels > 0:
        return bbr_levels * 3.0, "bbr_floors"

    bbr_alt_levels = _as_float(properties.get("byg055AfvigendeEtager"))
    if bbr_alt_levels and bbr_alt_levels > 0:
        return bbr_alt_levels * 3.0, "bbr_alt_floors"

    levels = _as_float(properties.get("building:levels"))
    if levels and levels > 0:
        return levels * 3.0, "building_levels"

    building_type = (properties.get("building") or "yes").lower()
    defaults = {
        "house": 8.0,
        "residential": 9.0,
        "apartments": 12.0,
        "commercial": 14.0,
        "retail": 12.0,
        "office": 15.0,
        "industrial": 11.0,
        "warehouse": 10.0,
        "hospital": 18.0,
        "hotel": 20.0,
        "school": 12.0,
        "church": 22.0,
        "cathedral": 25.0,
    }
    return defaults.get(building_type, 9.0), f"imputed_{building_type}"


def _load_buildings() -> list[dict]:
    """Load buildings and convert to UTM Shapely polygons."""
    path = DATA_DIR / "buildings.geojson"
    with open(path) as f:
        raw = json.load(f)

    features = raw.get("features", [])
    buildings = []
    skipped_nonpolygon = 0
    for feature in features:
        geom_json = feature.get("geometry")
        if not geom_json:
            continue

        geom = shape(geom_json)
        if geom.is_empty:
            continue
        if not geom.is_valid:
            geom = make_valid(geom)
            if geom.is_empty:
                continue
        if geom.geom_type not in ("Polygon", "MultiPolygon"):
            skipped_nonpolygon += 1
            continue

        geom_utm = transform(TO_UTM.transform, geom)
        props = feature.get("properties", {})
        height_m, height_source = _resolve_height_m(props)

        buildings.append(
            {
                "osm_id": props.get("osm_id"),
                "geom_utm": geom_utm,
                "height_m": height_m,
                "height_source": height_source,
                "building_type": (
                    props.get("building")
                    or props.get("byg021BygningensAnvendelse")
                    or "yes"
                ),
            }
        )

    print(
        f"Building load diagnostics: total_features={len(features)}, "
        f"usable_polygons={len(buildings)}, skipped_nonpolygon={skipped_nonpolygon}"
    )
    return buildings


CAFES = _load_cafes()
BUILDINGS = _load_buildings()
BUILDING_INDEX = build_building_index(BUILDINGS)
print(
    f"Loaded {len(CAFES)} cafes, {len(BUILDINGS)} buildings "
    f"({len(BUILDING_INDEX['records'])} indexed for shadows)"
)


# ---------- Endpoints ----------

def _parse_iso_datetime(value: str | None) -> datetime:
    if not value:
        return datetime.now(timezone.utc)
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _cafes_in_bbox(
    cafes: list[dict],
    min_lon: float,
    min_lat: float,
    max_lon: float,
    max_lat: float,
) -> list[dict]:
    bounded = []
    for cafe in cafes:
        coords = cafe.get("geometry", {}).get("coordinates", [None, None])
        lon, lat = coords
        if lon is None or lat is None:
            continue
        if min_lon <= lon <= max_lon and min_lat <= lat <= max_lat:
            bounded.append(cafe)
    return bounded


@app.get("/api/sunny")
def sunny_cafes(
    time: str = Query(None, description="ISO 8601 datetime, e.g. 2025-06-15T14:00:00Z"),
    min_lon: float | None = Query(None),
    min_lat: float | None = Query(None),
    max_lon: float | None = Query(None),
    max_lat: float | None = Query(None),
    limit: int = Query(200, ge=1, le=2000),
):
    """Return cafés ranked by sun score."""
    dt = _parse_iso_datetime(time)

    if None not in (min_lon, min_lat, max_lon, max_lat):
        cafes = _cafes_in_bbox(CAFES, min_lon, min_lat, max_lon, max_lat)
    else:
        cafes = CAFES

    try:
        cloud_cover = get_cloud_cover(dt)
    except Exception:
        cloud_cover = 50.0

    results = compute_sunny_cafes(cafes, BUILDING_INDEX, dt, cloud_cover, limit=limit)

    return {
        "time": dt.isoformat(),
        "cloud_cover_pct": cloud_cover,
        "count": len(results),
        "cafes": results,
    }


@app.get("/api/cafes")
def list_cafes():
    """Return all cafés (no sun computation)."""
    return {"cafes": CAFES}


class RecommendationPrefs(BaseModel):
    min_duration_min: int = Field(default=30, ge=0, le=24 * 60)
    preferred_periods: list[str] = Field(default_factory=lambda: ["morning", "lunch", "afternoon"])


class FavoriteRecommendationRequest(BaseModel):
    city_id: str = "copenhagen"
    favorite_ids: list[str] = Field(default_factory=list)
    days: int = Field(default=5, ge=1, le=5)
    prefs: RecommendationPrefs = Field(default_factory=RecommendationPrefs)


@app.get("/api/cities")
def list_cities():
    return {
        "cities": [
            {
                "city_id": city.city_id,
                "display_name": city.display_name,
                "timezone": city.timezone,
                "bbox": list(city.bbox),
            }
            for city in CITY_CONFIGS.values()
        ]
    }


@app.get("/api/cafe/{cafe_id}/sun-outlook")
def cafe_sun_outlook(
    cafe_id: str,
    city_id: str = Query("copenhagen"),
    days: int = Query(5, ge=1, le=5),
    include: str = Query("hourly,windows"),
    min_duration_min: int = Query(30, ge=0, le=24 * 60),
):
    include_parts = _parse_include(include)
    city = get_city_config(city_id)

    cache_key = cache_key_from_parts(
        city.city_id,
        cafe_id,
        str(days),
        ",".join(sorted(include_parts)),
        str(min_duration_min),
    )

    cached = read_cache(OUTLOOK_CACHE_ROOT, cache_key)
    if cached and cached.get("age_hours", 999) <= FRESH_TTL_HOURS:
        return _with_cache_status(cached.get("payload", {}), cached.get("age_hours"))

    cafe_feature = _find_cafe_feature(cafe_id)
    if cafe_feature is None:
        return {
            "cafe_id": cafe_id,
            "city_id": city.city_id,
            "timezone": city.timezone,
            "data_status": "unavailable",
            "freshness_hours": None,
            "provider_used": None,
            "fallback_used": False,
            "hourly": [],
            "windows": [],
            "generated_at_utc": datetime.now(timezone.utc).isoformat(),
            "error": "Cafe not found",
        }

    try:
        payload = _compute_cafe_outlook_payload(
            cafe_feature=cafe_feature,
            cafe_id=cafe_id,
            city_id=city.city_id,
            days=days,
            include_parts=include_parts,
            min_duration_min=min_duration_min,
        )
        write_cache(OUTLOOK_CACHE_ROOT, cache_key, {"payload": payload})
        return payload
    except Exception as exc:  # noqa: BLE001
        if cached:
            stale = _with_cache_status(cached.get("payload", {}), cached.get("age_hours"))
            stale["data_status"] = "stale"
            stale["fallback_used"] = True
            stale["error"] = f"Using cached outlook: {exc}"
            return stale
        return {
            "cafe_id": cafe_id,
            "city_id": city.city_id,
            "timezone": city.timezone,
            "data_status": "unavailable",
            "freshness_hours": None,
            "provider_used": None,
            "fallback_used": False,
            "hourly": [],
            "windows": [],
            "generated_at_utc": datetime.now(timezone.utc).isoformat(),
            "error": "Outlook unavailable",
            "error_detail": f"{type(exc).__name__}: {exc}",
        }


@app.post("/api/recommendations/favorites")
def favorites_recommendations(body: FavoriteRecommendationRequest):
    city = get_city_config(body.city_id)
    days = max(1, min(5, body.days))
    favorite_ids = list(dict.fromkeys(body.favorite_ids))
    prefs = body.prefs

    cache_key = cache_key_from_parts(
        city.city_id,
        ",".join(sorted(favorite_ids)),
        str(days),
        str(prefs.min_duration_min),
        ",".join(sorted(prefs.preferred_periods)),
    )
    cached = read_cache(RECOMMENDATIONS_CACHE_ROOT, cache_key)
    if cached and cached.get("age_hours", 999) <= FRESH_TTL_HOURS:
        return _with_cache_status(cached.get("payload", {}), cached.get("age_hours"))

    try:
        start_utc, end_utc = _outlook_range(days)
        weather = get_cloud_cover_series(city.city_id, start_utc, end_utc)

        windows_by_cafe: dict[str, dict] = {}
        for favorite_id in favorite_ids:
            feature = _find_cafe_feature(favorite_id)
            if feature is None:
                continue
            cafe_key = _feature_id(feature)
            cafe_name = feature.get("properties", {}).get("name") or "Cafe"
            hourly = _build_hourly_for_cafe(
                cafe_feature=feature,
                city_id=city.city_id,
                start_utc=start_utc,
                end_utc=end_utc,
                weather_cloud_by_hour=weather.cloud_by_hour,
            )
            windows = merge_windows(hourly, min_duration_min=prefs.min_duration_min)
            windows_by_cafe[cafe_key] = {
                "cafe_name": cafe_name,
                "windows": windows,
            }

        items = rank_recommendations(
            windows_by_cafe=windows_by_cafe,
            preferred_periods=prefs.preferred_periods,
            now_utc=datetime.now(timezone.utc),
        )

        payload = {
            "city_id": city.city_id,
            "timezone": city.timezone,
            "data_status": weather.data_status,
            "freshness_hours": weather.freshness_hours,
            "provider_used": weather.provider_used,
            "fallback_used": weather.fallback_used,
            "items": items,
            "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        }
        write_cache(RECOMMENDATIONS_CACHE_ROOT, cache_key, {"payload": payload})
        return payload
    except Exception as exc:  # noqa: BLE001
        if cached:
            stale = _with_cache_status(cached.get("payload", {}), cached.get("age_hours"))
            stale["data_status"] = "stale"
            stale["fallback_used"] = True
            stale["error"] = f"Using cached recommendations: {exc}"
            return stale

        return {
            "city_id": city.city_id,
            "timezone": city.timezone,
            "data_status": "unavailable",
            "freshness_hours": None,
            "provider_used": None,
            "fallback_used": False,
            "items": [],
            "generated_at_utc": datetime.now(timezone.utc).isoformat(),
            "error": "Recommendations unavailable",
        }


def _compute_cafe_outlook_payload(
    cafe_feature: dict,
    cafe_id: str,
    city_id: str,
    days: int,
    include_parts: set[str],
    min_duration_min: int,
) -> dict:
    city = get_city_config(city_id)
    start_utc, end_utc = _outlook_range(days)
    weather = get_cloud_cover_series(city.city_id, start_utc, end_utc)
    hourly = _build_hourly_for_cafe(
        cafe_feature=cafe_feature,
        city_id=city.city_id,
        start_utc=start_utc,
        end_utc=end_utc,
        weather_cloud_by_hour=weather.cloud_by_hour,
    )
    windows = merge_windows(hourly, min_duration_min=min_duration_min)

    return {
        "cafe_id": cafe_id,
        "city_id": city.city_id,
        "timezone": city.timezone,
        "data_status": weather.data_status,
        "freshness_hours": weather.freshness_hours,
        "provider_used": weather.provider_used,
        "fallback_used": weather.fallback_used,
        "hourly": hourly if "hourly" in include_parts else [],
        "windows": windows if "windows" in include_parts else [],
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
    }


def _build_hourly_for_cafe(
    cafe_feature: dict,
    city_id: str,
    start_utc: datetime,
    end_utc: datetime,
    weather_cloud_by_hour: dict[datetime, float],
) -> list[dict]:
    city = get_city_config(city_id)
    dt = start_utc
    rows: list[dict] = []
    now_utc = datetime.now(timezone.utc)
    while dt <= end_utc:
        cloud_cover = float(weather_cloud_by_hour.get(dt, 50.0))
        ranking = compute_sunny_cafes([cafe_feature], BUILDING_INDEX, dt, cloud_cover, limit=1)
        row = ranking[0] if ranking else _fallback_row(cafe_feature, cloud_cover)
        condition = classify_condition(row, cloud_cover)
        rows.append(
            {
                "time_utc": dt.isoformat(),
                "time_local": dt.astimezone(city.tz).isoformat(),
                "timezone": city.timezone,
                "condition": condition,
                "score": round(float(row.get("sunny_score", 0.0)), 1),
                "confidence_hint": confidence_hint(max(0.0, (dt - now_utc).total_seconds() / 3600.0)),
                "cloud_cover_pct": round(cloud_cover, 1),
            }
        )
        dt = dt + timedelta(hours=1)
    return rows


def _fallback_row(cafe_feature: dict, cloud_cover: float) -> dict:
    props = cafe_feature.get("properties", {})
    return {
        "sunny_score": 0.0,
        "sun_elevation_deg": float(props.get("sun_elevation_deg", 1.0)),
        "cloud_cover_pct": cloud_cover,
    }


def _parse_include(raw: str) -> set[str]:
    allowed = {"hourly", "windows"}
    parts = {part.strip().lower() for part in raw.split(",") if part.strip()}
    valid = parts & allowed
    return valid if valid else {"hourly", "windows"}


def _outlook_range(days: int) -> tuple[datetime, datetime]:
    now = datetime.now(timezone.utc).replace(minute=0, second=0, microsecond=0)
    end = now + timedelta(hours=(days * 24) - 1)
    return now, end


def _find_cafe_feature(cafe_id: str) -> dict | None:
    normalized = cafe_id.strip().lower()
    for feature in CAFES:
        if _feature_id(feature).lower() == normalized:
            return feature
    if normalized.startswith("osm-"):
        normalized = normalized[4:]
    try:
        osm_id = int(normalized)
    except Exception:
        return None
    for feature in CAFES:
        props = feature.get("properties", {})
        if props.get("osm_id") == osm_id:
            return feature
    return None


def _feature_id(feature: dict) -> str:
    props = feature.get("properties", {})
    osm_id = props.get("osm_id")
    if osm_id is not None:
        return f"osm-{osm_id}"
    name = (props.get("name") or "cafe").strip()
    coords = feature.get("geometry", {}).get("coordinates", [0, 0])
    lon = coords[0] if len(coords) > 0 else 0
    lat = coords[1] if len(coords) > 1 else 0
    return f"{name}-{lat}-{lon}"


def _with_cache_status(payload: dict, age_hours: float | None) -> dict:
    out = dict(payload)
    status = cache_status_from_age(age_hours)
    out["data_status"] = status
    out["freshness_hours"] = round(age_hours, 2) if age_hours is not None else out.get("freshness_hours")
    return out
