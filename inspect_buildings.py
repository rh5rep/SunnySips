"""Quick checks for building source/height coverage in data/buildings.geojson."""
from __future__ import annotations

import argparse
import json
import pathlib
from collections import Counter


def _to_float(value):
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


def _usable_vertical_value(props: dict) -> float | None:
    """
    Prefer explicit height; fallback to floor count proxies.
    """
    height = _to_float(props.get("height"))
    if height is not None and height > 0:
        return height
    bbr_floors = _to_float(props.get("byg054AntalEtager"))
    if bbr_floors is not None and bbr_floors > 0:
        return bbr_floors * 3.0
    bbr_alt_floors = _to_float(props.get("byg055AfvigendeEtager"))
    if bbr_alt_floors is not None and bbr_alt_floors > 0:
        return bbr_alt_floors * 3.0
    return None


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--path", default="data/buildings.geojson")
    parser.add_argument("--sample", type=int, default=10)
    args = parser.parse_args()

    path = pathlib.Path(args.path)
    if not path.exists():
        raise SystemExit(f"Missing file: {path}")

    raw = json.loads(path.read_text(encoding="utf-8"))
    features = raw.get("features", [])
    total = len(features)
    if total == 0:
        raise SystemExit("No building features found.")

    source_counter = Counter()
    geometry_counter = Counter()
    with_height = 0
    with_vertical_proxy = 0
    heights = []
    proxy_heights = []
    missing_examples = []
    present_examples = []

    for feat in features:
        props = feat.get("properties", {})
        source = props.get("source", "unknown")
        source_counter[source] += 1
        geometry_counter[feat.get("geometry", {}).get("type", "None")] += 1

        h = _to_float(props.get("height"))
        hv = _usable_vertical_value(props)
        if h is not None and h > 0:
            with_height += 1
            heights.append(h)
            if len(present_examples) < args.sample:
                present_examples.append(
                    {
                        "osm_id": props.get("osm_id"),
                        "source": source,
                        "height": h,
                        "building": props.get("building"),
                    }
                )
        else:
            if len(missing_examples) < args.sample:
                missing_examples.append(
                    {
                        "osm_id": props.get("osm_id"),
                        "source": source,
                        "height": props.get("height"),
                        "building": props.get("building"),
                    }
                )
        if hv is not None and hv > 0:
            with_vertical_proxy += 1
            proxy_heights.append(hv)

    pct = (100.0 * with_height) / total
    pct_proxy = (100.0 * with_vertical_proxy) / total
    print(f"file={path}")
    print(f"total_buildings={total}")
    print(f"with_explicit_height={with_height} ({pct:.2f}%)")
    print(f"with_usable_vertical_data={with_vertical_proxy} ({pct_proxy:.2f}%)")
    print(f"sources={dict(source_counter)}")
    print(f"geometry_types={dict(geometry_counter)}")
    if heights:
        heights_sorted = sorted(heights)
        mid = len(heights_sorted) // 2
        median = heights_sorted[mid]
        print(f"height_min={heights_sorted[0]:.2f}m")
        print(f"height_median={median:.2f}m")
        print(f"height_max={heights_sorted[-1]:.2f}m")
    if proxy_heights:
        proxy_sorted = sorted(proxy_heights)
        mid = len(proxy_sorted) // 2
        median_proxy = proxy_sorted[mid]
        print(f"proxy_height_min={proxy_sorted[0]:.2f}m")
        print(f"proxy_height_median={median_proxy:.2f}m")
        print(f"proxy_height_max={proxy_sorted[-1]:.2f}m")

    print("\nexamples_with_height:")
    for row in present_examples:
        print(row)

    print("\nexamples_missing_height:")
    for row in missing_examples:
        print(row)


if __name__ == "__main__":
    main()
