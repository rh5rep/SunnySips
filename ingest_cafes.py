"""Download Copenhagen cafés from OSM Overpass API."""
import json
import pathlib
import requests

OUTDIR = pathlib.Path("data")
OUTDIR.mkdir(parents=True, exist_ok=True)

# Copenhagen bounding box (WGS84)
BBOX_WGS84 = (55.615, 12.45, 55.735, 12.65)  # south, west, north, east

OVERPASS_URL = "https://overpass-api.de/api/interpreter"
OVERPASS_QUERY = f"""
[out:json][timeout:120];
(
  node["amenity"="cafe"]({BBOX_WGS84[0]},{BBOX_WGS84[1]},{BBOX_WGS84[2]},{BBOX_WGS84[3]});
  way["amenity"="cafe"]({BBOX_WGS84[0]},{BBOX_WGS84[1]},{BBOX_WGS84[2]},{BBOX_WGS84[3]});
  relation["amenity"="cafe"]({BBOX_WGS84[0]},{BBOX_WGS84[1]},{BBOX_WGS84[2]},{BBOX_WGS84[3]});
);
out center tags;
"""


def fetch_cafes() -> list[dict]:
    r = requests.post(OVERPASS_URL, data={"data": OVERPASS_QUERY}, timeout=120)
    r.raise_for_status()
    data = r.json()
    
    cafes = []
    for el in data["elements"]:
        # Nodes have lat/lon directly; ways/relations use 'center'
        lat = el.get("lat") or el.get("center", {}).get("lat")
        lon = el.get("lon") or el.get("center", {}).get("lon")
        if lat is None or lon is None:
            continue
        
        tags = el.get("tags", {})
        cafes.append({
            "type": "Feature",
            "properties": {
                "osm_id": el["id"],
                "name": tags.get("name", "Unknown Café"),
                "outdoor_seating": tags.get("outdoor_seating", "unknown"),
                "wheelchair": tags.get("wheelchair"),
            },
            "geometry": {
                "type": "Point",
                "coordinates": [lon, lat],
            },
        })
    return cafes


def main():
    cafes = fetch_cafes()
    geojson = {"type": "FeatureCollection", "features": cafes}
    out = OUTDIR / "cafes_copenhagen.geojson"
    out.write_text(json.dumps(geojson, ensure_ascii=False, indent=2))
    print(f"Saved {len(cafes)} cafés → {out}")


if __name__ == "__main__":
    main()
