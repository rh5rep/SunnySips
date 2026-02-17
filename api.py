"""FastAPI server for SunnySips."""
import json
import pathlib
from datetime import datetime, timezone

from fastapi import FastAPI, Query
from fastapi.middleware.cors import CORSMiddleware

from shadow_engine import TO_UTM, build_building_index, compute_sunny_cafes
from weather import get_cloud_cover
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
