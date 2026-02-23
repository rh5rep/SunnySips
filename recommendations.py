"""Shared sun outlook and recommendation computation for SunnySips."""

from __future__ import annotations

import hashlib
import json
import pathlib
from datetime import datetime, timedelta, timezone


UTC = timezone.utc
HEAVY_CLOUD_THRESHOLD = 90.0

OUTLOOK_CACHE_ROOT = pathlib.Path(".cache/sunnysips_v1/outlook")
RECOMMENDATIONS_CACHE_ROOT = pathlib.Path(".cache/sunnysips_v1/recommendations")
FRESH_TTL_HOURS = 2.0
STALE_TTL_HOURS = 12.0

AVAILABLE_CONDITIONS = {"sunny", "partial"}


def classify_condition(row: dict, cloud_cover_pct: float) -> str:
    elevation = float(row.get("sun_elevation_deg", 0.0))
    score = float(row.get("sunny_score", 0.0))
    if elevation <= 0:
        return "shaded"
    if cloud_cover_pct >= HEAVY_CLOUD_THRESHOLD:
        return "shaded"
    if score >= 55.0:
        return "sunny"
    if score >= 20.0:
        return "partial"
    return "shaded"


def merge_windows(hourly_rows: list[dict], min_duration_min: int = 30) -> list[dict]:
    if not hourly_rows:
        return []

    windows: list[dict] = []
    start_idx = None
    end_idx = None
    condition_scores: list[str] = []

    for idx, row in enumerate(hourly_rows):
        condition = row.get("condition", "shaded")
        available = condition in AVAILABLE_CONDITIONS
        if available:
            if start_idx is None:
                start_idx = idx
            end_idx = idx
            condition_scores.append(condition)
            continue

        if start_idx is not None and end_idx is not None:
            maybe = _build_window(hourly_rows, start_idx, end_idx, condition_scores)
            if maybe and maybe["duration_min"] >= min_duration_min:
                windows.append(maybe)
        start_idx = None
        end_idx = None
        condition_scores = []

    if start_idx is not None and end_idx is not None:
        maybe = _build_window(hourly_rows, start_idx, end_idx, condition_scores)
        if maybe and maybe["duration_min"] >= min_duration_min:
            windows.append(maybe)

    return windows


def rank_recommendations(
    windows_by_cafe: dict[str, dict],
    preferred_periods: list[str],
    now_utc: datetime | None = None,
) -> list[dict]:
    now_utc = _ensure_utc(now_utc or datetime.now(UTC))
    items: list[dict] = []

    for cafe_id, cafe_payload in windows_by_cafe.items():
        cafe_name = cafe_payload.get("cafe_name", "Unknown Cafe")
        windows = cafe_payload.get("windows", [])
        for window in windows:
            start = _parse_iso(window.get("start_utc"))
            end = _parse_iso(window.get("end_utc"))
            if start is None or end is None:
                continue
            if end <= now_utc:
                continue

            duration_min = int(window.get("duration_min", 0))
            condition = window.get("condition", "partial")
            hours_until = max(0.0, (start - now_utc).total_seconds() / 3600.0)

            duration_weight = min(40.0, duration_min / 3.0)
            condition_weight = 30.0 if condition == "sunny" else 15.0
            soonness_weight = max(0.0, 20.0 - (hours_until * 2.0))
            preferred_bonus = 10.0 if _window_matches_preference(start, preferred_periods) else 0.0

            score = round(duration_weight + condition_weight + soonness_weight + preferred_bonus, 2)

            reason_parts = []
            if duration_min >= 90:
                reason_parts.append("long sun window")
            elif duration_min >= 45:
                reason_parts.append("solid sun window")
            else:
                reason_parts.append("short sun window")

            if preferred_bonus > 0:
                reason_parts.append("matches preferred period")
            if condition == "sunny":
                reason_parts.append("high direct-sun potential")

            items.append(
                {
                    "cafe_id": cafe_id,
                    "cafe_name": cafe_name,
                    "start_utc": window.get("start_utc"),
                    "end_utc": window.get("end_utc"),
                    "start_local": window.get("start_local"),
                    "end_local": window.get("end_local"),
                    "duration_min": duration_min,
                    "condition": condition,
                    "score": score,
                    "reason": ", ".join(reason_parts),
                }
            )

    items.sort(key=lambda item: (-item["score"], item["start_utc"], item["cafe_name"]))
    return items


def cache_key_from_parts(*parts: str) -> str:
    raw = "|".join(parts)
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def read_cache(root: pathlib.Path, key: str) -> dict | None:
    path = _cache_file(root, key)
    if not path.exists():
        return None
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
        fetched_at = _parse_iso(payload.get("fetched_at"))
        if fetched_at is None:
            return None
        age_hours = (datetime.now(UTC) - fetched_at).total_seconds() / 3600.0
        if age_hours > STALE_TTL_HOURS:
            return None
        payload["age_hours"] = age_hours
        return payload
    except Exception:
        return None


def write_cache(root: pathlib.Path, key: str, payload: dict, fetched_at: datetime | None = None) -> None:
    path = _cache_file(root, key)
    body = {
        "fetched_at": _ensure_utc(fetched_at or datetime.now(UTC)).isoformat(),
        **payload,
    }
    path.write_text(json.dumps(body), encoding="utf-8")


def cache_status_from_age(age_hours: float | None) -> str:
    if age_hours is None:
        return "unavailable"
    if age_hours <= FRESH_TTL_HOURS:
        return "fresh"
    if age_hours <= STALE_TTL_HOURS:
        return "stale"
    return "unavailable"


def _build_window(hourly_rows: list[dict], start_idx: int, end_idx: int, conditions: list[str]) -> dict | None:
    if start_idx < 0 or end_idx >= len(hourly_rows):
        return None
    start_row = hourly_rows[start_idx]
    end_row = hourly_rows[end_idx]
    start = _parse_iso(start_row.get("time_utc"))
    end_start = _parse_iso(end_row.get("time_utc"))
    if start is None or end_start is None:
        return None
    end = end_start + timedelta(hours=1)
    duration_min = int((end - start).total_seconds() / 60.0)
    condition = "sunny" if all(c == "sunny" for c in conditions) else "partial"
    return {
        "start_utc": start_row.get("time_utc"),
        "end_utc": end.isoformat(),
        "start_local": start_row.get("time_local"),
        "end_local": _to_local_iso(end, start_row.get("timezone")),
        "duration_min": duration_min,
        "condition": condition,
    }


def _to_local_iso(utc_dt: datetime, timezone_name: str | None) -> str:
    if not timezone_name:
        return utc_dt.isoformat()
    try:
        from zoneinfo import ZoneInfo

        return utc_dt.astimezone(ZoneInfo(timezone_name)).isoformat()
    except Exception:
        return utc_dt.isoformat()


def _window_matches_preference(start_utc: datetime, preferred_periods: list[str]) -> bool:
    local_hour = start_utc.hour
    for period in preferred_periods:
        p = period.strip().lower()
        if p == "morning" and 6 <= local_hour < 11:
            return True
        if p == "lunch" and 11 <= local_hour < 14:
            return True
        if p == "afternoon" and 14 <= local_hour < 18:
            return True
        if p == "evening" and 18 <= local_hour < 22:
            return True
    return False


def _cache_file(root: pathlib.Path, key: str) -> pathlib.Path:
    root.mkdir(parents=True, exist_ok=True)
    return root / f"{key}.json"


def _parse_iso(raw: str | None) -> datetime | None:
    if not raw:
        return None
    try:
        parsed = datetime.fromisoformat(raw.replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=UTC)
        return parsed.astimezone(UTC)
    except Exception:
        return None


def _ensure_utc(dt: datetime) -> datetime:
    if dt.tzinfo is None:
        return dt.replace(tzinfo=UTC)
    return dt.astimezone(UTC)

