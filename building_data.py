import os
import time
import json
import pathlib
import requests
import xml.etree.ElementTree as ET
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

BASE_URL = "https://wfs.datafordeler.dk/GEODKV/GEODKV_WFS/1.0.0/WFS"
TYPENAME = "geodkv_v001:bygning_current"
SRS = "urn:ogc:def:crs:EPSG::25832"

# ✅ Correct env var usage
API_KEY = os.environ["DATAFORDELER_API_KEY"]

# Example bbox (EPSG:25832 meters). Replace with your area.
BBOX = (717338.52, 6166963.85, 729228.93, 6180953.56)  # minx, miny, maxx, maxy

OUTDIR = pathlib.Path("data/buildings")
OUTDIR.mkdir(parents=True, exist_ok=True)

def make_session() -> requests.Session:
    s = requests.Session()
    s.headers.update({"User-Agent": "zio-sun/0.1"})
    retry = Retry(
        total=5,
        backoff_factor=0.5,
        status_forcelist=[429, 500, 502, 503, 504],
        allowed_methods=["GET"],
        raise_on_status=False,
    )
    adapter = HTTPAdapter(max_retries=retry)
    s.mount("https://", adapter)
    s.mount("http://", adapter)
    return s

SESSION = make_session()

def wfs_get(params, timeout=60) -> requests.Response:
    params = dict(params)
    params["apikey"] = API_KEY
    r = SESSION.get(BASE_URL, params=params, timeout=timeout)

    # Raise for non-2xx
    r.raise_for_status()
    return r

def bbox_param() -> str:
    minx, miny, maxx, maxy = BBOX
    return f"{minx},{miny},{maxx},{maxy},{SRS}"

def parse_number_matched(xml_text: str) -> int | None:
    """
    WFS 2.0 'hits' responses include numberMatched on the FeatureCollection root.
    Parse robustly even with namespaces.
    """
    try:
        root = ET.fromstring(xml_text)
        # numberMatched is an attribute on the root element in most WFS 2.0 servers
        nm = root.attrib.get("numberMatched")
        return int(nm) if nm is not None else None
    except Exception:
        return None

def get_hits() -> int | None:
    params = {
        "service": "WFS",
        "version": "2.0.0",
        "request": "GetFeature",
        "typenames": TYPENAME,
        "srsName": SRS,
        "bbox": bbox_param(),
        "resultType": "hits",
    }
    r = wfs_get(params, timeout=60)
    return parse_number_matched(r.text)

def fetch_page(start_index: int, count: int = 1000, geojson=True) -> dict:
    params = {
        "service": "WFS",
        "version": "2.0.0",
        "request": "GetFeature",
        "typenames": TYPENAME,
        "srsName": SRS,
        "bbox": bbox_param(),
        "startIndex": start_index,
        "count": count,
    }
    if geojson:
        params["outputFormat"] = "application/json"

    r = wfs_get(params, timeout=120)

    # If server returned XML/GML instead of JSON, .json() will fail
    try:
        return r.json()
    except Exception:
        # Save raw response for inspection
        raw_path = OUTDIR / f"page_{start_index:07d}.raw.xml"
        raw_path.write_text(r.text)
        raise RuntimeError(
            f"Response was not JSON. Saved raw XML to {raw_path}. "
            "Try removing outputFormat or use ogr2ogr to convert GML."
        )

def main():
    try:
        matched = get_hits()
        print("numberMatched:", matched)
    except requests.exceptions.RequestException as e:
        print("Request failed (hits):", repr(e))
        return

    page_size = 1000
    start = 0
    page_num = 0

    while True:
        try:
            print(f"Fetching startIndex={start} count={page_size} ...")
            data = fetch_page(start, page_size, geojson=True)
        except requests.exceptions.RequestException as e:
            print("HTTP/network error:", repr(e))
            break
        except RuntimeError as e:
            print(str(e))
            break

        feats = data.get("features", [])
        if not feats:
            print("No features returned; stopping.")
            break

        outpath = OUTDIR / f"bygning_current_{page_num:04d}.geojson"
        outpath.write_text(json.dumps(data))
        print(f"Saved {len(feats)} features -> {outpath}")

        if len(feats) < page_size:
            print("Last page reached.")
            break

        start += page_size
        page_num += 1
        time.sleep(0.2)

    print("Done.")

if __name__ == "__main__":
    main()
