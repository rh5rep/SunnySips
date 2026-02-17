"""Cloud cover from Open-Meteo (free, no API key)."""
import requests
from datetime import datetime, timezone
from functools import lru_cache
from zoneinfo import ZoneInfo

OPEN_METEO_URL = "https://api.open-meteo.com/v1/forecast"

# Copenhagen coordinates
CPH_LAT = 55.676
CPH_LON = 12.568
CPH_TZ = ZoneInfo("Europe/Copenhagen")


@lru_cache(maxsize=16)
def _fetch_hourly_cloud_cover(date_str: str) -> dict[int, float]:
    """Fetch hourly cloud cover for Copenhagen for a given date. Cached."""
    params = {
        "latitude": CPH_LAT,
        "longitude": CPH_LON,
        "hourly": "cloudcover,direct_radiation",
        "timezone": "Europe/Copenhagen",
        "start_date": date_str,
        "end_date": date_str,
    }
    r = requests.get(OPEN_METEO_URL, params=params, timeout=30)
    r.raise_for_status()
    data = r.json()
    
    hourly = data.get("hourly", {})
    times = hourly.get("time", [])
    clouds = hourly.get("cloudcover", [])
    
    result = {}
    for t, c in zip(times, clouds):
        hour = int(t.split("T")[1].split(":")[0])
        result[hour] = float(c) if c is not None else 50.0
    return result


def get_cloud_cover(dt: datetime) -> float:
    """Get cloud cover % for Copenhagen at a given datetime."""
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    dt_local = dt.astimezone(CPH_TZ)

    date_str = dt_local.strftime("%Y-%m-%d")
    hourly = _fetch_hourly_cloud_cover(date_str)
    hour = dt_local.hour
    return hourly.get(hour, 50.0)
