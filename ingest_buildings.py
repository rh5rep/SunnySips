"""
Download Copenhagen building footprints + heights.

Strategy:
  1. Try ogr2ogr (GDAL) for bulk WFS download — fast, handles pagination internally.
  2. Fallback: OSM buildings via Overpass (less accurate heights but good coverage).
  3. Merge: prefer Datafordeler heights, fill gaps with OSM building:levels × 3.
"""
import json
import os
import pathlib
import subprocess
import sys
import argparse
import xml.etree.ElementTree as ET

import requests

OUTDIR = pathlib.Path("data")
OUTDIR.mkdir(parents=True, exist_ok=True)

def _sanitize_api_key(value: str) -> str:
    cleaned = value.strip()
    # Remove common quote characters accidentally included when pasting keys.
    quote_chars = "\"'`“”‘’"
    while cleaned and cleaned[0] in quote_chars:
        cleaned = cleaned[1:]
    while cleaned and cleaned[-1] in quote_chars:
        cleaned = cleaned[:-1]
    return cleaned.strip()


_RAW_API_KEY = os.environ.get("DATAFORDELER_API_KEY", "")
DATAFORDELER_API_KEY = _sanitize_api_key(_RAW_API_KEY)
if _RAW_API_KEY and DATAFORDELER_API_KEY != _RAW_API_KEY:
    print("⚠  Sanitized DATAFORDELER_API_KEY (removed extra quotes/whitespace).")

# EPSG:25832 (ETRS89 / UTM zone 32N) is the Danish standard CRS
# Copenhagen bounding box (approx) in EPSG:4326
CPH_BBOX = (12.45, 55.60, 12.65, 55.75)  # (minlon, minlat, maxlon, maxlat)
DATAFORDELER_WFS_URL = "https://wfs.datafordeler.dk/BBR/BBR_WFS/1.0.0/WFS"
DATAFORDELER_TYPENAME = "bygning_current"

DATAFORDELER_OUT = OUTDIR / "buildings_datafordeler.geojson"
OSM_OUT = OUTDIR / "buildings_osm.geojson"
MERGED_OUT = OUTDIR / "buildings.geojson"
POLYGON_TYPES = {"Polygon", "MultiPolygon"}


def _local_name(tag: str) -> str:
    if "}" in tag:
        return tag.rsplit("}", 1)[-1]
    return tag


def _discover_datafordeler_typenames(apikey: str) -> list[str]:
    """Discover WFS typenames from GetCapabilities and return building-like names first."""
    params = {
        "service": "WFS",
        "version": "2.0.0",
        "request": "GetCapabilities",
        "apikey": apikey,
    }
    try:
        resp = requests.get(DATAFORDELER_WFS_URL, params=params, timeout=60)
        resp.raise_for_status()
    except requests.RequestException as e:
        print(f"⚠  Could not fetch Datafordeler capabilities: {e}")
        return []

    try:
        root = ET.fromstring(resp.content)
    except ET.ParseError:
        print("⚠  Could not parse Datafordeler capabilities XML.")
        return []

    typenames: list[str] = []
    for feature_type in root.iter():
        if _local_name(feature_type.tag) != "FeatureType":
            continue
        for child in feature_type:
            if _local_name(child.tag) == "Name" and child.text:
                typenames.append(child.text.strip())
                break

    # Unique while preserving order
    seen = set()
    ordered = []
    for name in typenames:
        if name and name not in seen:
            ordered.append(name)
            seen.add(name)

    building_first = [
        n for n in ordered if ("bygning" in n.lower() or "building" in n.lower())
    ]
    rest = [n for n in ordered if n not in building_first]
    return building_first + rest


def _is_building_typename(name: str) -> bool:
    lowered = name.lower()
    return "bygning" in lowered or "building" in lowered

def _safe_load_features(path: pathlib.Path, label: str) -> list[dict]:
    """Load GeoJSON features with resilient error handling."""
    if not path.exists():
        return []
    if path.stat().st_size == 0:
        print(f"⚠  {label} file is empty: {path}")
        return []
    try:
        with open(path, encoding="utf-8") as f:
            raw = json.load(f)
        feats = raw.get("features", [])
        if not isinstance(feats, list):
            print(f"⚠  {label} has invalid GeoJSON structure: {path}")
            return []
        return feats
    except json.JSONDecodeError:
        print(f"⚠  {label} is not valid JSON: {path}")
        return []


def _geometry_counts(features: list[dict]) -> dict[str, int]:
    counts: dict[str, int] = {}
    for feat in features:
        gtype = feat.get("geometry", {}).get("type", "None")
        counts[gtype] = counts.get(gtype, 0) + 1
    return counts


def _polygon_features(features: list[dict]) -> list[dict]:
    return [
        feat
        for feat in features
        if feat.get("geometry", {}).get("type") in POLYGON_TYPES
    ]


def fetch_datafordeler_ogr2ogr(
    typename: str = DATAFORDELER_TYPENAME,
    allow_non_building_fallback: bool = False,
) -> bool:
    """Use ogr2ogr to download building footprints from Datafordeler WFS."""
    if not DATAFORDELER_API_KEY:
        print(
            "⚠  DATAFORDELER_API_KEY not set, skipping Datafordeler."
        )
        return False

    discovered = _discover_datafordeler_typenames(DATAFORDELER_API_KEY)
    if allow_non_building_fallback:
        fallback = discovered
    else:
        fallback = [n for n in discovered if _is_building_typename(n)]
    candidates = [typename] + [n for n in fallback if n != typename]
    if discovered:
        print(
            f"→ Found {len(discovered)} typenames in capabilities "
            f"(trying {len(candidates)}; building-like first)."
        )

    print("→ Running ogr2ogr for Datafordeler WFS …")
    for idx, candidate_typename in enumerate(candidates, start=1):
        wfs_url = (
            f"WFS:{DATAFORDELER_WFS_URL}"
            f"?service=WFS&version=2.0.0&request=GetFeature"
            f"&typenames={candidate_typename}"
            f"&apikey={DATAFORDELER_API_KEY}"
        )
        tmp_out = DATAFORDELER_OUT.with_suffix(".tmp.geojson")
        cmd = [
            "ogr2ogr",
            "-f", "GeoJSON",
            str(tmp_out),
            wfs_url,
            "-spat", str(CPH_BBOX[0]), str(CPH_BBOX[1]), str(CPH_BBOX[2]), str(CPH_BBOX[3]),
            "-spat_srs", "EPSG:4326",
            "-t_srs", "EPSG:4326",
            "-progress",
        ]
        print(f"  [{idx}/{len(candidates)}] typename={candidate_typename}")
        try:
            subprocess.run(cmd, check=True, timeout=300)
            if not tmp_out.exists() or tmp_out.stat().st_size == 0:
                continue
            features = _safe_load_features(tmp_out, "Datafordeler")
            if not features:
                continue
            if not _is_building_typename(candidate_typename):
                print(
                    f"⚠  Downloaded typename '{candidate_typename}', which is not building-like. "
                    "Skipping to avoid contaminating building dataset."
                )
                continue
            polygon_feats = _polygon_features(features)
            if not polygon_feats:
                counts = _geometry_counts(features)
                print(
                    f"⚠  Typename '{candidate_typename}' returned no polygon footprints "
                    f"(geometry types: {counts}). Skipping."
                )
                continue
            tmp_out.write_text(
                json.dumps({"type": "FeatureCollection", "features": polygon_feats}),
                encoding="utf-8",
            )
            tmp_out.replace(DATAFORDELER_OUT)
            print(
                f"✓ Saved {len(polygon_feats)} Datafordeler building footprints "
                f"(typename={candidate_typename}) → {DATAFORDELER_OUT}"
            )
            return True
        except FileNotFoundError:
            print("⚠  ogr2ogr not found. Install GDAL: brew install gdal")
            return False
        except subprocess.CalledProcessError:
            continue
        except subprocess.TimeoutExpired:
            continue
        finally:
            if tmp_out.exists():
                try:
                    tmp_out.unlink()
                except OSError:
                    pass

    print(
        "⚠  Datafordeler download produced no readable output for all tried typenames. "
        "Check API access scope."
    )
    return False


OVERPASS_URL = "https://overpass-api.de/api/interpreter"

OVERPASS_QUERY = f"""
[out:json][timeout:120];
(
  way["building"]({CPH_BBOX[1]},{CPH_BBOX[0]},{CPH_BBOX[3]},{CPH_BBOX[2]});
  relation["building"]({CPH_BBOX[1]},{CPH_BBOX[0]},{CPH_BBOX[3]},{CPH_BBOX[2]});
);
out body;
>;
out skel qt;
"""


def fetch_osm_buildings() -> bool:
    """Download building footprints from OpenStreetMap via Overpass API."""
    print("→ Fetching OSM buildings via Overpass …")
    try:
        resp = requests.post(OVERPASS_URL, data={"data": OVERPASS_QUERY}, timeout=180)
        resp.raise_for_status()
    except requests.RequestException as e:
        print(f"✗ Overpass request failed: {e}")
        return False

    osm_data = resp.json()
    features = _osm_to_geojson(osm_data)

    geojson = {"type": "FeatureCollection", "features": features}
    OSM_OUT.write_text(json.dumps(geojson), encoding="utf-8")
    print(f"✓ Saved {len(features)} buildings → {OSM_OUT}")
    return True


def _osm_to_geojson(data: dict) -> list[dict]:
    """Convert Overpass JSON response to GeoJSON features."""
    nodes = {}
    ways = {}

    for el in data.get("elements", []):
        if el["type"] == "node":
            nodes[el["id"]] = (el["lon"], el["lat"])
        elif el["type"] == "way":
            ways[el["id"]] = el

    features = []
    for way in ways.values():
        coords = [nodes[nid] for nid in way.get("nodes", []) if nid in nodes]
        if len(coords) < 4:
            continue

        tags = way.get("tags", {})
        height = _extract_height(tags)

        feature = {
            "type": "Feature",
            "properties": {
                "osm_id": way["id"],
                "height": height,
                "building": tags.get("building", "yes"),
                "source": "osm",
            },
            "geometry": {
                "type": "Polygon",
                "coordinates": [coords],
            },
        }
        features.append(feature)

    return features


def _extract_height(tags: dict) -> float | None:
    """Extract building height from OSM tags."""
    if "height" in tags:
        try:
            return float(tags["height"].replace("m", "").strip())
        except ValueError:
            pass
    if "building:levels" in tags:
        try:
            return float(tags["building:levels"]) * 3.0
        except ValueError:
            pass
    return None


def merge_buildings(include_datafordeler: bool = True, include_osm: bool = True):
    """Merge Datafordeler and OSM building data, preferring Datafordeler heights."""
    features = []

    # Load Datafordeler buildings if available
    df_count = 0
    if include_datafordeler:
        for feat in _safe_load_features(DATAFORDELER_OUT, "Datafordeler"):
            if feat.get("geometry", {}).get("type") not in POLYGON_TYPES:
                continue
            feat.setdefault("properties", {})
            feat["properties"]["source"] = "datafordeler"
            features.append(feat)
            df_count += 1

    # Load OSM buildings
    osm_count = 0
    if include_osm:
        for feat in _safe_load_features(OSM_OUT, "OSM"):
            if feat.get("geometry", {}).get("type") not in POLYGON_TYPES:
                continue
            features.append(feat)
            osm_count += 1

    # If no data at all, fail
    if not features:
        print("✗ No building data available.")
        sys.exit(1)

    merged = {"type": "FeatureCollection", "features": features}
    MERGED_OUT.write_text(json.dumps(merged), encoding="utf-8")
    print(
        f"✓ Merged {len(features)} buildings "
        f"({df_count} Datafordeler + {osm_count} OSM) → {MERGED_OUT}"
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--only-datafordeler",
        action="store_true",
        help="Fetch only Datafordeler (skip OSM fallback).",
    )
    parser.add_argument(
        "--only-osm",
        action="store_true",
        help="Fetch only OSM buildings.",
    )
    parser.add_argument(
        "--typename",
        default=DATAFORDELER_TYPENAME,
        help=f"Datafordeler WFS typename (default: {DATAFORDELER_TYPENAME}).",
    )
    parser.add_argument(
        "--allow-non-building-fallback",
        action="store_true",
        help="Also try non-building typenames discovered in capabilities (not recommended).",
    )
    args = parser.parse_args()
    if args.only_datafordeler and args.only_osm:
        print("✗ Choose only one of --only-datafordeler or --only-osm.")
        sys.exit(2)

    # Step 1: try Datafordeler via ogr2ogr
    got_df = False
    got_osm = False
    if not args.only_osm:
        got_df = fetch_datafordeler_ogr2ogr(
            typename=args.typename,
            allow_non_building_fallback=args.allow_non_building_fallback,
        )

    # Step 2: always fetch OSM as fallback / gap filler
    if not args.only_datafordeler:
        got_osm = fetch_osm_buildings()

    if not got_df and not got_osm:
        print("✗ Could not fetch buildings from any source.")
        sys.exit(1)

    # Step 3: merge
    merge_buildings(
        include_datafordeler=not args.only_osm,
        include_osm=not args.only_datafordeler,
    )


if __name__ == "__main__":
    main()
