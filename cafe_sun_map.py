"""Generate interactive OpenStreetMap HTML for cafe sun/shade in Copenhagen.

No extra Python packages are required. The output file uses Leaflet via CDN.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import webbrowser
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

import api
from shadow_engine import compute_sunny_cafes
from weather import get_cloud_cover

AREA_BBOXES = {
    "core-cph": (12.500, 55.660, 12.640, 55.730),
    "indre-by": (12.560, 55.675, 12.600, 55.695),
    "norrebro": (12.520, 55.680, 12.590, 55.720),
    "frederiksberg": (12.500, 55.660, 12.560, 55.700),
    "osterbro": (12.560, 55.690, 12.640, 55.730),
}
NEIGHBORHOOD_BBOXES = {
    "Indre By": AREA_BBOXES["indre-by"],
    "Norrebro": AREA_BBOXES["norrebro"],
    "Frederiksberg": AREA_BBOXES["frederiksberg"],
    "Osterbro": AREA_BBOXES["osterbro"],
}
CPH_TZ = ZoneInfo("Europe/Copenhagen")


def _parse_time(value: str | None) -> datetime:
    if not value:
        return datetime.now(timezone.utc)
    dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=CPH_TZ)
    return dt.astimezone(timezone.utc)


def _bucket(sunny_fraction: float) -> str:
    if sunny_fraction >= 0.99:
        return "sunny"
    if sunny_fraction <= 0.01:
        return "shaded"
    return "partial"


def _resolve_bbox(area: str) -> tuple[float, float, float, float]:
    if area not in AREA_BBOXES:
        raise SystemExit(
            f"Unknown area '{area}'. Choices: {', '.join(sorted(AREA_BBOXES.keys()))}"
        )
    return AREA_BBOXES[area]


def _detect_neighborhood(lon: float, lat: float) -> str:
    for name, (min_lon, min_lat, max_lon, max_lat) in NEIGHBORHOOD_BBOXES.items():
        if min_lon <= lon <= max_lon and min_lat <= lat <= max_lat:
            return name
    return "Other"


def _apply_filters(
    rows: list[dict],
    only: str,
    neighborhood: str,
    min_score: float,
    name_query: str | None,
    max_items: int,
) -> list[dict]:
    query = (name_query or "").strip().lower()
    filtered = []
    for row in rows:
        if float(row.get("sunny_score", 0.0)) < min_score:
            continue
        if only != "all" and _bucket(float(row.get("sunny_fraction", 0.0))) != only:
            continue
        if neighborhood != "all" and row.get("neighborhood") != neighborhood:
            continue
        if query and query not in row.get("name", "").lower():
            continue
        filtered.append(row)
    return filtered[:max_items]


def _build_html(rows: list[dict], cloud_cover: float, local_label: str, area: str) -> str:
    data_json = json.dumps(rows, ensure_ascii=False)
    neighborhoods = sorted({row.get("neighborhood", "Other") for row in rows})
    neighborhood_options = "\n".join(
        f'        <option value="{n}">{n}</option>' for n in neighborhoods
    )
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>SunnySips Indre By</title>
  <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
  <style>
    html, body, #map {{ height: 100%; margin: 0; }}
    .panel {{
      position: absolute;
      top: 12px;
      left: 12px;
      z-index: 1000;
      background: rgba(255,255,255,0.98);
      border: 1px solid #d9d9d9;
      border-radius: 10px;
      padding: 10px 12px;
      width: 280px;
      font: 13px/1.4 -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, sans-serif;
      box-shadow: 0 4px 14px rgba(0,0,0,0.15);
    }}
    .panel h3 {{ margin: 0 0 6px; font-size: 14px; }}
    .meta {{ color: #444; margin-bottom: 8px; }}
    .row {{ margin: 6px 0; }}
    .legend {{ margin-top: 8px; color: #333; }}
    .legend span {{ display: inline-block; width: 14px; text-align: center; margin-right: 4px; }}
  </style>
</head>
<body>
  <div id="map"></div>
  <div class="panel">
    <h3>SunnySips: {area}</h3>
    <div class="meta">Time: {local_label}<br>Cloud cover: {cloud_cover:.1f}%</div>
    <div class="row">
      <label for="neighborhood">Neighborhood:</label>
      <select id="neighborhood">
        <option value="all">All</option>
{neighborhood_options}
      </select>
    </div>
    <div class="row">
      <label for="bucket">Bucket:</label>
      <select id="bucket">
        <option value="all">All</option>
        <option value="sunny">Sunny</option>
        <option value="partial">Partial</option>
        <option value="shaded">Shaded</option>
      </select>
    </div>
    <div class="row">
      <label for="minScore">Min score: <span id="minScoreVal">0</span></label><br>
      <input id="minScore" type="range" min="0" max="100" value="0" step="1" />
    </div>
    <div class="row">
      <label for="nameQuery">Name contains:</label><br>
      <input id="nameQuery" type="text" placeholder="e.g. coffee" />
    </div>
    <div class="row"><b>Visible cafes:</b> <span id="count">0</span></div>
    <div class="legend">
      <div><span style="color:#10b981;">●</span>Sunny (100%)</div>
      <div><span style="color:#f59e0b;">●</span>Partial (33%/67%)</div>
      <div><span style="color:#ef4444;">●</span>Shaded (0%)</div>
    </div>
  </div>

  <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
  <script>
    const cafes = {data_json};

    function bucketOf(row) {{
      const v = Number(row.sunny_fraction || 0);
      if (v >= 0.99) return "sunny";
      if (v <= 0.01) return "shaded";
      return "partial";
    }}
    function styleFor(bucket) {{
      if (bucket === "sunny") return {{ color: "#10b981", radius: 7 }};
      if (bucket === "partial") return {{ color: "#f59e0b", radius: 6 }};
      return {{ color: "#ef4444", radius: 5 }};
    }}
    function osmLink(row) {{
      if (!row.osm_id) return "";
      return `https://www.openstreetmap.org/node/${{row.osm_id}}`;
    }}
    function streetViewLink(row) {{
      if (row.lat == null || row.lon == null) return "";
      return `https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=${{row.lat}},${{row.lon}}`;
    }}
    function popupHtml(row) {{
      const url = osmLink(row);
      const sv = streetViewLink(row);
      const parts = [];
      if (url) parts.push(`<a href="${{url}}" target="_blank" rel="noopener noreferrer">Open OSM</a>`);
      if (sv) parts.push(`<a href="${{sv}}" target="_blank" rel="noopener noreferrer">Street View</a>`);
      const links = parts.join(" | ");
      return `
        <b>${{row.name || "Unknown Cafe"}}</b><br>
        Score: ${{Number(row.sunny_score || 0).toFixed(1)}}<br>
        Sunny fraction: ${{Math.round(100 * Number(row.sunny_fraction || 0))}}%<br>
        Cloud cover: ${{Number(row.cloud_cover_pct || 50).toFixed(1)}}%<br>
        Sun elevation: ${{Number(row.sun_elevation_deg || 0).toFixed(2)}}°<br>
        ${{links}}
      `;
    }}

    const centerLat = cafes.reduce((a, r) => a + Number(r.lat), 0) / Math.max(cafes.length, 1);
    const centerLon = cafes.reduce((a, r) => a + Number(r.lon), 0) / Math.max(cafes.length, 1);
    const map = L.map("map").setView([centerLat || 55.684, centerLon || 12.58], 15);
    L.tileLayer("https://{{s}}.tile.openstreetmap.org/{{z}}/{{x}}/{{y}}.png", {{
      maxZoom: 19,
      attribution: '&copy; OpenStreetMap contributors'
    }}).addTo(map);

    const layer = L.layerGroup().addTo(map);
    const markerEntries = cafes.map(row => {{
      const bucket = bucketOf(row);
      const s = styleFor(bucket);
      const marker = L.circleMarker([Number(row.lat), Number(row.lon)], {{
        radius: s.radius,
        color: s.color,
        weight: 1.5,
        fillColor: s.color,
        fillOpacity: 0.85
      }}).bindPopup(popupHtml(row));
      marker.bindTooltip(`${{row.name || "Unknown Cafe"}} (${{Number(row.sunny_score || 0).toFixed(1)}})`);
      return {{ row, bucket, marker }};
    }});

    const bucketEl = document.getElementById("bucket");
    const neighborhoodEl = document.getElementById("neighborhood");
    const minScoreEl = document.getElementById("minScore");
    const minScoreValEl = document.getElementById("minScoreVal");
    const nameQueryEl = document.getElementById("nameQuery");
    const countEl = document.getElementById("count");

    function applyFilters() {{
      layer.clearLayers();
      const selectedBucket = bucketEl.value;
      const selectedNeighborhood = neighborhoodEl.value;
      const minScore = Number(minScoreEl.value);
      const query = nameQueryEl.value.trim().toLowerCase();
      minScoreValEl.textContent = String(minScore);

      let shown = 0;
      for (const entry of markerEntries) {{
        const row = entry.row;
        if (Number(row.sunny_score || 0) < minScore) continue;
        if (selectedBucket !== "all" && entry.bucket !== selectedBucket) continue;
        if (selectedNeighborhood !== "all" && row.neighborhood !== selectedNeighborhood) continue;
        if (query && !(row.name || "").toLowerCase().includes(query)) continue;
        entry.marker.addTo(layer);
        shown += 1;
      }}
      countEl.textContent = String(shown);
    }}

    neighborhoodEl.addEventListener("change", applyFilters);
    bucketEl.addEventListener("change", applyFilters);
    minScoreEl.addEventListener("input", applyFilters);
    nameQueryEl.addEventListener("input", applyFilters);
    applyFilters();
  </script>
</body>
</html>
"""


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--time",
        default=None,
        help="ISO datetime. If timezone is omitted, Europe/Copenhagen is assumed.",
    )
    parser.add_argument(
        "--only",
        choices=["all", "sunny", "partial", "shaded"],
        default="all",
        help="Server-side prefilter before writing HTML.",
    )
    parser.add_argument(
        "--area",
        choices=sorted(AREA_BBOXES.keys()),
        default="core-cph",
        help="Area preset. Default includes Indre By, Norrebro, Frederiksberg, Osterbro.",
    )
    parser.add_argument(
        "--neighborhood",
        choices=["all", "Indre By", "Norrebro", "Frederiksberg", "Osterbro", "Other"],
        default="all",
        help="Server-side neighborhood prefilter.",
    )
    parser.add_argument("--min-score", type=float, default=0.0)
    parser.add_argument("--name", default=None, help="Server-side case-insensitive name filter.")
    parser.add_argument(
        "--cloud-cover",
        type=float,
        default=None,
        help="Override cloud cover percentage (0-100).",
    )
    parser.add_argument("--max-items", type=int, default=1200)
    parser.add_argument(
        "--output",
        default="output/sunny_cph_map.html",
        help="Output HTML path.",
    )
    parser.add_argument(
        "--open",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Open the generated HTML in your browser (default: true).",
    )
    args = parser.parse_args()

    dt = _parse_time(args.time)
    min_lon, min_lat, max_lon, max_lat = _resolve_bbox(args.area)
    cafes = api._cafes_in_bbox(api.CAFES, min_lon, min_lat, max_lon, max_lat)
    if not cafes:
        raise SystemExit(f"No cafes found in area '{args.area}'.")

    if args.cloud_cover is None:
        try:
            cloud_cover = float(get_cloud_cover(dt))
        except Exception:
            cloud_cover = 50.0
    else:
        cloud_cover = max(0.0, min(100.0, float(args.cloud_cover)))

    rows = compute_sunny_cafes(cafes, api.BUILDING_INDEX, dt, cloud_cover, limit=None)
    for row in rows:
        row["neighborhood"] = _detect_neighborhood(float(row["lon"]), float(row["lat"]))
    rows = _apply_filters(
        rows=rows,
        only=args.only,
        neighborhood=args.neighborhood,
        min_score=max(0.0, float(args.min_score)),
        name_query=args.name,
        max_items=max(1, args.max_items),
    )
    if not rows:
        raise SystemExit("No cafes matched the selected filters.")

    out_path = pathlib.Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    local_label = dt.astimezone(CPH_TZ).isoformat()
    out_path.write_text(
        _build_html(rows, cloud_cover, local_label, args.area),
        encoding="utf-8",
    )

    print(f"Saved map: {out_path}")
    print(f"Rows exported: {len(rows)}")
    print(f"Area: {args.area}")
    print(f"Time (Copenhagen): {local_label}")
    print(f"Cloud cover: {cloud_cover:.1f}%")
    if args.open:
        webbrowser.open(out_path.resolve().as_uri())
        print("Opened in browser.")


if __name__ == "__main__":
    main()
