"""Generate static JSON snapshots for SunnySips and write them to disk.

This script is intended for GitHub Actions + GitHub Pages deployment.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import sys
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

ROOT_DIR = pathlib.Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

import api
from shadow_engine import compute_sunny_cafes
from weather import get_cloud_cover

CPH_TZ = ZoneInfo("Europe/Copenhagen")

AREAS = {
    "core-cph": (12.500, 55.660, 12.640, 55.730),
    "indre-by": (12.560, 55.675, 12.600, 55.695),
    "norrebro": (12.520, 55.680, 12.590, 55.720),
    "frederiksberg": (12.500, 55.660, 12.560, 55.700),
    "osterbro": (12.560, 55.690, 12.640, 55.730),
}


def _parse_time(value: str | None) -> datetime:
    if not value:
        return datetime.now(timezone.utc)
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _bucket(sunny_fraction: float) -> str:
    if sunny_fraction >= 0.99:
        return "sunny"
    if sunny_fraction <= 0.01:
        return "shaded"
    return "partial"


def _summarize(rows: list[dict]) -> dict:
    if not rows:
        return {
            "total": 0,
            "sunny": 0,
            "partial": 0,
            "shaded": 0,
            "avg_score": 0.0,
        }
    sunny = 0
    partial = 0
    shaded = 0
    score_sum = 0.0
    for row in rows:
        b = _bucket(float(row.get("sunny_fraction", 0.0)))
        if b == "sunny":
            sunny += 1
        elif b == "partial":
            partial += 1
        else:
            shaded += 1
        score_sum += float(row.get("sunny_score", 0.0))
    return {
        "total": len(rows),
        "sunny": sunny,
        "partial": partial,
        "shaded": shaded,
        "avg_score": round(score_sum / len(rows), 2),
    }


def _write_json(path: pathlib.Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")


def _build_index_page(generated_at_utc: str, area_files: list[dict]) -> str:
    rows = "\n".join(
        f"<li><a href=\"latest/{row['file']}\">{row['area']}</a> ({row['count']} cafes)</li>"
        for row in area_files
    )
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>SunnySips Snapshots</title>
  <style>
    body {{
      font: 16px/1.45 -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, sans-serif;
      margin: 2rem;
      color: #1f2937;
    }}
    code {{ background: #f3f4f6; padding: 2px 6px; border-radius: 6px; }}
  </style>
</head>
<body>
  <h1>SunnySips Snapshots</h1>
  <p>Generated at (UTC): <code>{generated_at_utc}</code></p>
  <p>JSON index: <a href="latest/index.json">latest/index.json</a></p>
  <ul>
    {rows}
  </ul>
</body>
</html>
"""


def _to_preview_rows(rows: list[dict], top_n: int = 2000) -> list[dict]:
    preview = []
    for row in rows[:top_n]:
        item = dict(row)
        item["bucket"] = _bucket(float(row.get("sunny_fraction", 0.0)))
        preview.append(item)
    return preview


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output-dir",
        default="site/latest",
        help="Directory where area snapshots are written.",
    )
    parser.add_argument(
        "--time",
        default=None,
        help="ISO timestamp in UTC. Default is now.",
    )
    parser.add_argument(
        "--areas",
        nargs="*",
        default=sorted(AREAS.keys()),
        help=f"Area keys to generate. Choices: {', '.join(sorted(AREAS.keys()))}",
    )
    parser.add_argument(
        "--hours-ahead",
        type=int,
        default=0,
        help="Also produce hourly forecasts up to this many hours ahead.",
    )
    args = parser.parse_args()

    requested_areas = []
    for area in args.areas:
        if area not in AREAS:
            raise SystemExit(
                f"Unknown area '{area}'. Choices: {', '.join(sorted(AREAS.keys()))}"
            )
        requested_areas.append(area)

    base_dt = _parse_time(args.time)
    generated_at = datetime.now(timezone.utc)
    output_dir = pathlib.Path(args.output_dir)
    site_dir = output_dir.parent
    site_dir.mkdir(parents=True, exist_ok=True)
    output_dir.mkdir(parents=True, exist_ok=True)

    time_slots = [base_dt]
    for h in range(1, max(0, args.hours_ahead) + 1):
        time_slots.append(base_dt + timedelta(hours=h))

    area_index = []
    print(f"Generating snapshots for {len(requested_areas)} areas and {len(time_slots)} time slot(s)...")

    for area in requested_areas:
        min_lon, min_lat, max_lon, max_lat = AREAS[area]
        cafes = api._cafes_in_bbox(api.CAFES, min_lon, min_lat, max_lon, max_lat)
        if not cafes:
            payload = {
                "generated_at_utc": generated_at.isoformat(),
                "area": area,
                "bbox": [min_lon, min_lat, max_lon, max_lat],
                "error": "No cafes in bbox",
                "snapshots": [],
            }
            _write_json(output_dir / f"{area}.json", payload)
            area_index.append({"area": area, "file": f"{area}.json", "count": 0})
            continue

        snapshots = []
        for dt in time_slots:
            try:
                cloud_cover = float(get_cloud_cover(dt))
            except Exception:
                cloud_cover = 50.0
            rows = compute_sunny_cafes(
                cafes,
                api.BUILDING_INDEX,
                dt,
                cloud_cover,
                limit=None,
            )
            snapshots.append(
                {
                    "time_utc": dt.isoformat(),
                    "time_local": dt.astimezone(CPH_TZ).isoformat(),
                    "cloud_cover_pct": round(cloud_cover, 1),
                    "summary": _summarize(rows),
                    "cafes": _to_preview_rows(rows),
                }
            )

        payload = {
            "generated_at_utc": generated_at.isoformat(),
            "area": area,
            "bbox": [min_lon, min_lat, max_lon, max_lat],
            "snapshots": snapshots,
        }
        _write_json(output_dir / f"{area}.json", payload)

        first_count = snapshots[0]["summary"]["total"] if snapshots else 0
        area_index.append({"area": area, "file": f"{area}.json", "count": first_count})
        print(f"  - {area}: {first_count} cafes")

    index_payload = {
        "generated_at_utc": generated_at.isoformat(),
        "areas": area_index,
    }
    _write_json(output_dir / "index.json", index_payload)
    (site_dir / "index.html").write_text(
        _build_index_page(generated_at.isoformat(), area_index),
        encoding="utf-8",
    )
    print(f"Wrote snapshots to {output_dir}")


if __name__ == "__main__":
    main()
