#!/usr/bin/env python3
"""Build a deterministic, offline traffic-calibration snapshot from Brussels Mobility.

Sources are official Brussels Mobility open data:
- traffic counts API (devices + live measurements)
- WFS bm_traffic:traffic_live_geom in EPSG:31370

The runtime never needs network access. This tool captures source data, converts official
Lambert 72 coordinates to Grand Bruxelles local metres, preserves measurement windows,
and records SHA-256 hashes/provenance. Speed is intentionally not promoted to a gameplay
speed truth because Brussels Mobility documents that those speed values are not calibrated
for absolute speed-limit compliance.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import statistics
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

ORIGIN_E = 147868.29422791934
ORIGIN_N = 169538.62414926197

DEVICES_URL = "https://data.mobility.brussels/traffic/api/counts/?request=devices&outputFormat=json"
LIVE_URL = (
    "https://data.mobility.brussels/traffic/api/counts/"
    "?request=live&interval=60&includeLanes=false&singleValue=true"
)
WFS_URL = (
    "https://data.mobility.brussels/geoserver/bm_traffic/wfs"
    "?service=wfs&version=1.1.0&request=GetFeature"
    "&typeName=bm_traffic:traffic_live_geom&outputFormat=json&srsName=EPSG:31370"
)

FORMAT = "grand-bruxelles-brussels-mobility-traffic-v1"
SOURCE_NAME = "Bruxelles Mobilite / Brussels Mobility"
LICENSE = "CC0-1.0"

ID_KEYS = (
    "featureid", "feature_id", "featureID", "id", "name", "code", "device",
    "traverse", "traverse_id", "site", "site_id", "fid",
)
DESCRIPTION_KEYS = ("descr", "description", "libelle", "label", "street", "road")
ORIENTATION_KEYS = ("orientation", "orientation_deg", "bearing")
LANE_KEYS = ("number_of_lanes", "lanes", "lane_count", "nlanes")
COUNT_KEYS = ("count", "volume", "vehicles", "vehicules")
OCCUPANCY_KEYS = ("occupancy", "occupation", "occupancy_pct")
FROM_KEYS = ("from", "start", "start_time", "from_timestamp")
TO_KEYS = ("to", "end", "end_time", "to_timestamp")


def _canonical_bytes(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def _sha256(value: Any) -> str:
    return hashlib.sha256(_canonical_bytes(value)).hexdigest()


def _fetch_json(url: str, timeout: float = 45.0) -> Any:
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": "Grand-Bruxelles-Game/traffic-calibration (+GitHub Chatnoir01)",
            "Accept": "application/json, application/geo+json;q=0.9, */*;q=0.1",
        },
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        charset = response.headers.get_content_charset() or "utf-8"
        return json.loads(response.read().decode(charset))


def _load_or_fetch(path: Path | None, url: str) -> Any:
    if path is None:
        return _fetch_json(url)
    return json.loads(path.read_text(encoding="utf-8"))


def _first(mapping: dict[str, Any], keys: Iterable[str], default: Any = None) -> Any:
    for key in keys:
        if key in mapping and mapping[key] not in (None, ""):
            return mapping[key]
    lowered = {str(k).lower(): v for k, v in mapping.items()}
    for key in keys:
        candidate = lowered.get(str(key).lower())
        if candidate not in (None, ""):
            return candidate
    return default


def _to_float(value: Any) -> float | None:
    if value is None or isinstance(value, bool):
        return None
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number if math.isfinite(number) else None


def _to_int(value: Any) -> int | None:
    number = _to_float(value)
    if number is None:
        return None
    return int(round(number))


def _parse_time(value: Any) -> datetime | None:
    if value in (None, ""):
        return None
    text = str(value).strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _duration_minutes(start: Any, end: Any) -> float | None:
    start_dt = _parse_time(start)
    end_dt = _parse_time(end)
    if start_dt is None or end_dt is None or end_dt <= start_dt:
        return None
    return round((end_dt - start_dt).total_seconds() / 60.0, 3)


def _extract_point(geometry: Any) -> tuple[float, float] | None:
    if not isinstance(geometry, dict):
        return None
    geometry_type = geometry.get("type")
    coordinates = geometry.get("coordinates")
    if geometry_type == "Point" and isinstance(coordinates, list) and len(coordinates) >= 2:
        east = _to_float(coordinates[0])
        north = _to_float(coordinates[1])
        if east is not None and north is not None:
            return east, north
    if geometry_type == "MultiPoint" and isinstance(coordinates, list) and coordinates:
        first = coordinates[0]
        if isinstance(first, list) and len(first) >= 2:
            east = _to_float(first[0])
            north = _to_float(first[1])
            if east is not None and north is not None:
                return east, north
    return None


def _game_position(east: float, north: float) -> list[float]:
    return [round(east - ORIGIN_E, 3), round(-(north - ORIGIN_N), 3)]


def _feature_identifier(feature: dict[str, Any]) -> str:
    properties = feature.get("properties") if isinstance(feature.get("properties"), dict) else {}
    value = _first(properties, ID_KEYS)
    if value not in (None, ""):
        return str(value)
    if feature.get("id") not in (None, ""):
        return str(feature["id"]).split(".")[-1]
    return ""


def _geometry_records(document: Any) -> list[dict[str, Any]]:
    if not isinstance(document, dict):
        return []
    features = document.get("features")
    if not isinstance(features, list):
        return []
    result: list[dict[str, Any]] = []
    for feature in features:
        if not isinstance(feature, dict):
            continue
        point = _extract_point(feature.get("geometry"))
        if point is None:
            continue
        props = feature.get("properties") if isinstance(feature.get("properties"), dict) else {}
        identifier = _feature_identifier(feature)
        east, north = point
        result.append(
            {
                "id": identifier,
                "lambert72": [round(east, 3), round(north, 3)],
                "game": _game_position(east, north),
                "description": str(_first(props, DESCRIPTION_KEYS, "")),
                "orientation_deg": _to_float(_first(props, ORIENTATION_KEYS)),
                "number_of_lanes": _to_int(_first(props, LANE_KEYS)),
                "properties": props,
            }
        )
    return result


def _device_records(document: Any) -> list[dict[str, Any]]:
    # The public API has used both list-shaped and keyed object-shaped responses.
    root = document
    if isinstance(document, dict):
        for key in ("devices", "traverses", "features", "data"):
            if key in document and isinstance(document[key], (list, dict)):
                root = document[key]
                break
    result: list[dict[str, Any]] = []
    if isinstance(root, dict):
        iterator = root.items()
    elif isinstance(root, list):
        iterator = ((str(index), item) for index, item in enumerate(root))
    else:
        return result
    for fallback_id, raw in iterator:
        if not isinstance(raw, dict):
            continue
        identifier = str(_first(raw, ID_KEYS, fallback_id))
        result.append(
            {
                "id": identifier,
                "description": str(_first(raw, DESCRIPTION_KEYS, "")),
                "orientation_deg": _to_float(_first(raw, ORIENTATION_KEYS)),
                "number_of_lanes": _to_int(_first(raw, LANE_KEYS)),
            }
        )
    return result


def _looks_like_measurement(mapping: dict[str, Any]) -> bool:
    return _first(mapping, COUNT_KEYS) is not None and (
        _first(mapping, FROM_KEYS) is not None or _first(mapping, TO_KEYS) is not None
    )


def _live_records(document: Any) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []

    def walk(node: Any, path: list[str]) -> None:
        if isinstance(node, dict):
            if _looks_like_measurement(node):
                explicit_id = _first(node, ID_KEYS)
                meaningful_path = [p for p in path if p.lower() not in {"live", "data", "values", "t1", "t2", "latest"}]
                identifier = str(explicit_id if explicit_id not in (None, "") else (meaningful_path[-1] if meaningful_path else ""))
                start = _first(node, FROM_KEYS)
                end = _first(node, TO_KEYS)
                count = _to_float(_first(node, COUNT_KEYS))
                occupancy = _to_float(_first(node, OCCUPANCY_KEYS))
                records.append(
                    {
                        "id": identifier,
                        "count": count,
                        "occupancy_pct": occupancy,
                        "from": None if start is None else str(start),
                        "to": None if end is None else str(end),
                        "duration_minutes": _duration_minutes(start, end),
                    }
                )
                return
            for key, value in node.items():
                walk(value, path + [str(key)])
        elif isinstance(node, list):
            for index, value in enumerate(node):
                walk(value, path + [str(index)])

    walk(document, [])
    # Keep one latest-ish record per identifier, preferring a valid end timestamp.
    grouped: dict[str, dict[str, Any]] = {}
    for record in records:
        identifier = record["id"]
        previous = grouped.get(identifier)
        if previous is None:
            grouped[identifier] = record
            continue
        previous_end = _parse_time(previous.get("to"))
        current_end = _parse_time(record.get("to"))
        if current_end is not None and (previous_end is None or current_end >= previous_end):
            grouped[identifier] = record
    return list(grouped.values())


def _norm_id(value: str) -> str:
    return "".join(ch.lower() for ch in value if ch.isalnum())


def _index_by_id(records: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for record in records:
        identifier = str(record.get("id", ""))
        if identifier:
            result[_norm_id(identifier)] = record
    return result


def _nearest_name_match(identifier: str, candidates: dict[str, dict[str, Any]]) -> dict[str, Any] | None:
    key = _norm_id(identifier)
    if not key:
        return None
    if key in candidates:
        return candidates[key]
    # WFS IDs may carry workspace/table prefixes while API IDs do not.
    for candidate_key, candidate in candidates.items():
        if candidate_key and (candidate_key.endswith(key) or key.endswith(candidate_key)):
            return candidate
    return None


def _quantile(values: list[float], fraction: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    if len(ordered) == 1:
        return round(ordered[0], 3)
    index = (len(ordered) - 1) * fraction
    lower = math.floor(index)
    upper = math.ceil(index)
    if lower == upper:
        return round(ordered[lower], 3)
    value = ordered[lower] + (ordered[upper] - ordered[lower]) * (index - lower)
    return round(value, 3)


def build_snapshot(devices: Any, live: Any, geometry: Any, captured_at: datetime | None = None) -> dict[str, Any]:
    captured = (captured_at or datetime.now(timezone.utc)).astimezone(timezone.utc)
    geometry_records = _geometry_records(geometry)
    device_index = _index_by_id(_device_records(devices))
    live_index = _index_by_id(_live_records(live))

    sensors: list[dict[str, Any]] = []
    for geo in geometry_records:
        identifier = str(geo.get("id", ""))
        device = _nearest_name_match(identifier, device_index) or {}
        measurement = _nearest_name_match(identifier, live_index) or {}
        sensor = {
            "id": identifier,
            "description": device.get("description") or geo.get("description") or "",
            "orientation_deg": device.get("orientation_deg") if device.get("orientation_deg") is not None else geo.get("orientation_deg"),
            "number_of_lanes": device.get("number_of_lanes") if device.get("number_of_lanes") is not None else geo.get("number_of_lanes"),
            "lambert72": geo["lambert72"],
            "game": geo["game"],
            "measurement": {
                "count": measurement.get("count"),
                "occupancy_pct": measurement.get("occupancy_pct"),
                "from": measurement.get("from"),
                "to": measurement.get("to"),
                "duration_minutes": measurement.get("duration_minutes"),
            },
        }
        sensors.append(sensor)

    counts = [float(s["measurement"]["count"]) for s in sensors if s["measurement"]["count"] is not None and float(s["measurement"]["count"]) >= 0.0]
    occupancies = [float(s["measurement"]["occupancy_pct"]) for s in sensors if s["measurement"]["occupancy_pct"] is not None and float(s["measurement"]["occupancy_pct"]) >= 0.0]
    measured = sum(1 for sensor in sensors if sensor["measurement"]["count"] is not None)

    return {
        "format": FORMAT,
        "captured_at_utc": captured.isoformat().replace("+00:00", "Z"),
        "source": {
            "name": SOURCE_NAME,
            "license": LICENSE,
            "api_docs": "https://data.mobility.brussels/traffic/api/counts/",
            "devices_url": DEVICES_URL,
            "live_url": LIVE_URL,
            "geometry_url": WFS_URL,
            "geometry_layer": "bm_traffic:traffic_live_geom",
            "geometry_crs": "EPSG:31370",
            "notes": [
                "Live counts are retained with their source measurement window; no hourly rate is assumed.",
                "Occupancy may be used as a congestion signal.",
                "Source speed values are deliberately excluded from calibration because they are not calibrated for absolute speed compliance.",
            ],
        },
        "coordinate_system": {
            "source_crs": "EPSG:31370",
            "origin_e": ORIGIN_E,
            "origin_n": ORIGIN_N,
            "axes": "X=east, Y=up, Z=south",
            "units": "metres",
        },
        "raw_sha256": {
            "devices": _sha256(devices),
            "live": _sha256(live),
            "geometry": _sha256(geometry),
        },
        "stats": {
            "geometry_sensor_count": len(sensors),
            "measured_sensor_count": measured,
            "count_median": None if not counts else round(statistics.median(counts), 3),
            "count_p25": _quantile(counts, 0.25),
            "count_p75": _quantile(counts, 0.75),
            "occupancy_median_pct": None if not occupancies else round(statistics.median(occupancies), 3),
        },
        "sensors": sensors,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--devices-file", type=Path)
    parser.add_argument("--live-file", type=Path)
    parser.add_argument("--geometry-file", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--min-geometry-sensors", type=int, default=1)
    parser.add_argument("--min-measured-sensors", type=int, default=1)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    devices = _load_or_fetch(args.devices_file, DEVICES_URL)
    live = _load_or_fetch(args.live_file, LIVE_URL)
    geometry = _load_or_fetch(args.geometry_file, WFS_URL)
    snapshot = build_snapshot(devices, live, geometry)
    stats = snapshot["stats"]
    if int(stats["geometry_sensor_count"]) < args.min_geometry_sensors:
        raise SystemExit(f"Brussels Mobility geometry gate failed: {stats['geometry_sensor_count']} < {args.min_geometry_sensors}")
    if int(stats["measured_sensor_count"]) < args.min_measured_sensors:
        raise SystemExit(f"Brussels Mobility live-match gate failed: {stats['measured_sensor_count']} < {args.min_measured_sensors}")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(snapshot, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        "BRUSSELS_MOBILITY_TRAFFIC_SNAPSHOT_OK: %d geometry sensors, %d live matched -> %s"
        % (stats["geometry_sensor_count"], stats["measured_sensor_count"], args.output)
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
