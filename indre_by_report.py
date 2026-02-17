"""Print sunny cafe ranking for Indre By for now and selected times."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

import api
from shadow_engine import compute_sunny_cafes
from weather import get_cloud_cover

# Indre By bounding box (approx): min_lon, min_lat, max_lon, max_lat
INDRE_BY_BBOX = (12.560, 55.675, 12.600, 55.695)
CPH_TZ = ZoneInfo("Europe/Copenhagen")


def _parse_time(value: str) -> datetime:
    dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=CPH_TZ)
    return dt.astimezone(timezone.utc)


def _print_top_rows(rows: list[dict], top: int) -> None:
    print("rank | score | sun% | cloud% | name")
    print("-" * 64)
    for idx, row in enumerate(rows[:top], start=1):
        cloud_pct = float(row.get("cloud_cover_pct", 50.0))
        print(
            f"{idx:>4} | {row['sunny_score']:>5.1f} | "
            f"{100 * row['sunny_fraction']:>4.0f}% | "
            f"{cloud_pct:>6.1f}% | {row['name']}"
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--times",
        nargs="*",
        default=[],
        help=(
            "ISO timestamps. If omitted, uses now plus two example times. "
            "Example: 2026-06-15T12:00:00+02:00"
        ),
    )
    parser.add_argument("--top", type=int, default=15)
    args = parser.parse_args()

    if args.times:
        datetimes = [_parse_time(t) for t in args.times]
    else:
        now_utc = datetime.now(timezone.utc)
        today_local = now_utc.astimezone(CPH_TZ).date()
        defaults_local = [
            datetime.combine(today_local, datetime.min.time(), tzinfo=CPH_TZ).replace(hour=9),
            datetime.combine(today_local, datetime.min.time(), tzinfo=CPH_TZ).replace(hour=12),
            datetime.combine(today_local, datetime.min.time(), tzinfo=CPH_TZ).replace(hour=16),
        ]
        datetimes = [now_utc] + [d.astimezone(timezone.utc) for d in defaults_local]

    min_lon, min_lat, max_lon, max_lat = INDRE_BY_BBOX
    cafes = api._cafes_in_bbox(api.CAFES, min_lon, min_lat, max_lon, max_lat)
    if not cafes:
        raise SystemExit("No cafes found in Indre By bbox.")

    print(f"Indre By cafes in bbox: {len(cafes)}")
    print(f"BBox: {INDRE_BY_BBOX}")
    print()

    for dt in datetimes:
        try:
            cloud = get_cloud_cover(dt)
        except Exception:
            cloud = 50.0
        rows = compute_sunny_cafes(cafes, api.BUILDING_INDEX, dt, cloud, limit=args.top)
        local_label = dt.astimezone(CPH_TZ).isoformat()
        print(f"time={local_label}  cloud={cloud:.1f}%")
        _print_top_rows(rows, args.top)
        print()


if __name__ == "__main__":
    main()
