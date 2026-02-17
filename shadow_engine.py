"""2.5D shadow computation for Copenhagen cafes."""
from __future__ import annotations

import math
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

import numpy as np
import pyproj
from pysolar.solar import get_altitude, get_azimuth
from shapely import make_valid
from shapely.affinity import translate
from shapely.errors import GEOSException
from shapely.geometry import MultiPolygon, Point, Polygon
from shapely.ops import unary_union
from shapely.strtree import STRtree

from seating_heuristic import estimate_seating_point

# Transformer: WGS84 -> EPSG:25832 (UTM zone 32N, meters)
TO_UTM = pyproj.Transformer.from_crs("EPSG:4326", "EPSG:25832", always_xy=True)
TO_WGS = pyproj.Transformer.from_crs("EPSG:25832", "EPSG:4326", always_xy=True)

# Max shadow length cap (prevents absurd shadows at very low sun)
MAX_SHADOW_LENGTH = 500.0  # meters
# Min sun elevation to consider (below this -> no direct sun possible)
MIN_SUN_ELEVATION = 2.0  # degrees


@dataclass(frozen=True)
class BuildingRecord:
    """Building geometry and resolved height used for shadow casting."""

    geom_utm: Polygon | MultiPolygon
    height_m: float
    osm_id: int | None
    height_source: str


def _to_utc(dt: datetime) -> datetime:
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def get_sun_position(lat: float, lon: float, dt: datetime) -> tuple[float, float]:
    """Return (azimuth_deg, elevation_deg) for a WGS84 point and timestamp."""
    dt_utc = _to_utc(dt)
    elevation = float(get_altitude(lat, lon, dt_utc))
    azimuth = (float(get_azimuth(lat, lon, dt_utc)) + 360.0) % 360.0
    return azimuth, elevation


def _azimuth_to_vector(azimuth_deg: float, length: float) -> tuple[float, float]:
    """Convert north-clockwise azimuth to x/y offsets in meters (east/north)."""
    radians = math.radians(azimuth_deg)
    dx = math.sin(radians) * length
    dy = math.cos(radians) * length
    return dx, dy


def _iter_polygons(geom: Polygon | MultiPolygon) -> list[Polygon]:
    if isinstance(geom, Polygon):
        if geom.is_empty:
            return []
        return [geom]
    if isinstance(geom, MultiPolygon):
        return [poly for poly in geom.geoms if not poly.is_empty]
    return []


def _shadow_for_polygon(poly: Polygon, dx: float, dy: float):
    """
    Create a shadow volume in 2D by bridging each exterior edge to its projected edge.
    """
    if not poly.is_valid:
        repaired = make_valid(poly)
        candidates = _iter_polygons(repaired) if repaired.geom_type in ("Polygon", "MultiPolygon") else []
        if not candidates:
            return None
        poly = max(candidates, key=lambda p: p.area)

    shifted = translate(poly, xoff=dx, yoff=dy)
    pieces = [poly, shifted]

    exterior = list(poly.exterior.coords)
    for i in range(len(exterior) - 1):
        p1 = exterior[i]
        p2 = exterior[i + 1]
        quad = Polygon(
            [
                p1,
                p2,
                (p2[0] + dx, p2[1] + dy),
                (p1[0] + dx, p1[1] + dy),
            ]
        )
        if not quad.is_empty and quad.is_valid:
            pieces.append(quad)

    try:
        return unary_union(pieces)
    except GEOSException:
        repaired_pieces = []
        for g in pieces:
            cleaned = g if g.is_valid else make_valid(g)
            if cleaned.geom_type in ("Polygon", "MultiPolygon"):
                repaired_pieces.append(cleaned)
        if not repaired_pieces:
            return None
        return unary_union(repaired_pieces)


def project_shadow(
    building_geom: Polygon | MultiPolygon,
    height_m: float,
    sun_azimuth_deg: float,
    sun_elevation_deg: float,
):
    """Return a shadow polygon for a building, or None if no shadow should be cast."""
    if sun_elevation_deg <= MIN_SUN_ELEVATION or height_m <= 0:
        return None

    tan_elev = math.tan(math.radians(sun_elevation_deg))
    if tan_elev <= 0:
        return None

    shadow_length = min(MAX_SHADOW_LENGTH, height_m / tan_elev)
    if shadow_length <= 0:
        return None

    shadow_azimuth = (sun_azimuth_deg + 180.0) % 360.0
    dx, dy = _azimuth_to_vector(shadow_azimuth, shadow_length)

    pieces = []
    for poly in _iter_polygons(building_geom):
        shadow = _shadow_for_polygon(poly, dx, dy)
        if not shadow.is_empty:
            pieces.append(shadow)

    if not pieces:
        return None
    if len(pieces) == 1:
        return pieces[0]
    return unary_union(pieces)


def build_building_index(buildings: list[dict[str, Any]]) -> dict[str, Any]:
    """
    Build a spatial index bundle once at startup and reuse for every request.
    """
    records: list[BuildingRecord] = []
    geometries = []

    for item in buildings:
        geom = item.get("geom_utm") or item.get("geometry_utm") or item.get("geometry")
        if geom is None or geom.is_empty:
            continue
        if geom.geom_type not in ("Polygon", "MultiPolygon"):
            continue

        height = float(item.get("height_m") or 0.0)
        if height <= 0:
            continue

        records.append(
            BuildingRecord(
                geom_utm=geom,
                height_m=height,
                osm_id=item.get("osm_id"),
                height_source=item.get("height_source", "unknown"),
            )
        )
        geometries.append(geom)

    index = STRtree(geometries) if geometries else None
    id_map = {id(g): idx for idx, g in enumerate(geometries)}
    max_height = max((rec.height_m for rec in records), default=20.0)

    return {
        "records": records,
        "geometries": geometries,
        "index": index,
        "id_map": id_map,
        "max_height_m": max_height,
    }


def _query_candidate_indices(index_bundle: dict[str, Any], search_area) -> list[int]:
    tree = index_bundle.get("index")
    if tree is None:
        return []

    result = tree.query(search_area)
    if len(result) == 0:
        return []

    first = result[0]
    if isinstance(first, (int, np.integer)):
        return [int(i) for i in result]

    id_map = index_bundle.get("id_map", {})
    return [id_map[id(g)] for g in result if id(g) in id_map]


def _candidate_seating_points(cafe_lon: float, cafe_lat: float) -> list[tuple[float, float]]:
    """
    MVP terrace uncertainty model:
    - one south-shifted point
    - two nearby lateral variants to avoid single-point brittleness
    """
    base_lon, base_lat = estimate_seating_point(cafe_lon, cafe_lat, offset_meters=5.0)
    meters_per_degree_lon = max(1.0, 111_320.0 * math.cos(math.radians(cafe_lat)))
    lon_jitter = 2.5 / meters_per_degree_lon
    return [
        (base_lon, base_lat),
        (base_lon - lon_jitter, base_lat),
        (base_lon + lon_jitter, base_lat),
    ]


def _cloud_factor(cloud_cover_pct: float) -> float:
    cloud_cover_pct = max(0.0, min(100.0, float(cloud_cover_pct)))
    return 1.0 - (cloud_cover_pct / 100.0)


def compute_sunny_cafes(
    cafes: list[dict],
    buildings: list[dict] | dict[str, Any],
    dt: datetime,
    cloud_cover_pct: float,
    limit: int | None = 200,
) -> list[dict]:
    """
    Rank cafes by direct sun score (geometry x weather).
    """
    if not cafes:
        return []

    index_bundle = buildings if isinstance(buildings, dict) and "index" in buildings else build_building_index(buildings)  # type: ignore[arg-type]
    records: list[BuildingRecord] = index_bundle.get("records", [])

    dt_utc = _to_utc(dt)
    # Copenhagen-scale requests can share one sun position without meaningful loss.
    ref_lon, ref_lat = 12.568, 55.676
    sun_azimuth_deg, sun_elevation_deg = get_sun_position(ref_lat, ref_lon, dt_utc)

    weather_factor = _cloud_factor(cloud_cover_pct)
    results = []

    if sun_elevation_deg <= MIN_SUN_ELEVATION:
        for feature in cafes:
            props = feature.get("properties", {})
            geom = feature.get("geometry", {})
            coords = geom.get("coordinates", [None, None])
            results.append(
                {
                    "osm_id": props.get("osm_id"),
                    "name": props.get("name", "Unknown Cafe"),
                    "lon": coords[0],
                    "lat": coords[1],
                    "sunny_score": 0.0,
                    "sunny_fraction": 0.0,
                    "in_shadow": True,
                    "sun_elevation_deg": round(sun_elevation_deg, 2),
                    "sun_azimuth_deg": round(sun_azimuth_deg, 2),
                    "cloud_cover_pct": round(float(cloud_cover_pct), 1),
                }
            )
        return results[:limit] if limit else results

    tan_elevation = math.tan(math.radians(sun_elevation_deg))
    max_height_m = float(index_bundle.get("max_height_m", 20.0))
    max_shadow_search = min(MAX_SHADOW_LENGTH, max_height_m / tan_elevation) if tan_elevation > 0 else MAX_SHADOW_LENGTH

    shadow_cache: dict[int, Any] = {}
    for feature in cafes:
        props = feature.get("properties", {})
        geom = feature.get("geometry", {})
        lon, lat = geom.get("coordinates", [None, None])
        if lon is None or lat is None:
            continue

        seating_points_lonlat = _candidate_seating_points(lon, lat)
        sunny_count = 0

        for seat_lon, seat_lat in seating_points_lonlat:
            x, y = TO_UTM.transform(seat_lon, seat_lat)
            seat_point = Point(x, y)
            search_area = seat_point.buffer(max_shadow_search + 3.0)
            candidate_indices = _query_candidate_indices(index_bundle, search_area)

            shaded = False
            for idx in candidate_indices:
                if idx in shadow_cache:
                    shadow_poly = shadow_cache[idx]
                else:
                    rec = records[idx]
                    shadow_poly = project_shadow(
                        rec.geom_utm,
                        rec.height_m,
                        sun_azimuth_deg,
                        sun_elevation_deg,
                    )
                    shadow_cache[idx] = shadow_poly

                if shadow_poly is not None and shadow_poly.covers(seat_point):
                    shaded = True
                    break

            if not shaded:
                sunny_count += 1

        sunny_fraction = sunny_count / max(1, len(seating_points_lonlat))
        sunny_score = round(100.0 * sunny_fraction * weather_factor, 1)

        results.append(
            {
                "osm_id": props.get("osm_id"),
                "name": props.get("name", "Unknown Cafe"),
                "lon": lon,
                "lat": lat,
                "sunny_score": sunny_score,
                "sunny_fraction": round(sunny_fraction, 3),
                "in_shadow": sunny_fraction == 0.0,
                "sun_elevation_deg": round(sun_elevation_deg, 2),
                "sun_azimuth_deg": round(sun_azimuth_deg, 2),
                "cloud_cover_pct": round(float(cloud_cover_pct), 1),
            }
        )

    results.sort(key=lambda r: (r["sunny_score"], r["sunny_fraction"], r["name"]), reverse=True)
    if limit:
        return results[:limit]
    return results
