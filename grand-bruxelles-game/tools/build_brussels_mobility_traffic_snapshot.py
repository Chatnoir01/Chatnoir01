#!/usr/bin/env python3
"""Build an offline, source-backed Brussels Mobility traffic calibration snapshot.

The snapshot is intentionally generated outside Godot. Runtime gameplay reads a committed
JSON snapshot and therefore never depends on the network. Official detector geometry is
requested in EPSG:31370 and converted to the project's local metre coordinate system.

Brussels Mobility documents traffic counts and occupancy as useful measurements, while
its detector speed values are not calibrated for absolute speed-limit compliance. Speed is
therefore deliberately excluded from this calibration artifact.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import statistics
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ORIGIN_E = 147868.29422791934
ORIGIN_N = 169538.62414926197
FORMAT = "grand-bruxelles-brussels-mobility-traffic-v1"
LICENSE = "CC0-1.0"
SOURCE_NAME = "Bruxelles Mobilite / Brussels Mobility"
FRESH_MAX_AGE_MINUTES = 10.0

DEVICES_URL = "https://data.mobility.brussels/traffic/api/counts/?request=devices&outputFormat=json"
LIVE_URL = "https://data.mobility.brussels/traffic/api/counts/?request=live&interval=1&includeLanes=false&singleValue=true"
WFS_URL = (
    "https://data.mobility.brussels/geoserver/bm_traffic/wfs"
    "?service=wfs&version=1.1.0&request=GetFeature"
    "&typeName=bm_traffic:traffic_live_geom&outputFormat=json&srsName=EPSG:31370"
)


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def sha256_json(value: Any) -> str:
    return hashlib.sha256(canonical_bytes(value)).hexdigest()


def fetch_json(url: str, timeout: float = 45.0) -> Any:
    request = urllib.request.Request(url, headers={"User-Agent": "Grand-Bruxelles-Game/traffic-calibration (+GitHub Chatnoir01)", "Accept": "application/json, application/geo+json;q=0.9, */*;q=0.1"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        raw = response.read()
        if raw[:2] == b"\x1f\x8b":
            import gzip
            raw = gzip.decompress(raw)
        charset = response.headers.get_content_charset() or "utf-8"
        return json.loads(raw.decode(charset))


def load_or_fetch(path: Path | None, url: str) -> Any:
    return json.loads(path.read_text(encoding="utf-8")) if path else fetch_json(url)


def as_float(value: Any) -> float | None:
    if value is None or isinstance(value, bool):
        return None
    try:
        result = float(value)
    except (TypeError, ValueError):
        return None
    return result if math.isfinite(result) else None


def as_int(value: Any) -> int | None:
    number = as_float(value)
    return None if number is None else int(round(number))


def parse_time(value: Any) -> datetime | None:
    if value in (None, "", "-"):
        return None
    text = str(value).strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        parsed = None
    if parsed is None:
        for pattern in ("%Y/%m/%d %H:%M", "%Y/%m/%d %H:%M:%S"):
            try:
                parsed = datetime.strptime(str(value).strip(), pattern)
                break
            except ValueError:
                continue
    if parsed is None:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def duration_minutes(start: Any, end: Any) -> float | None:
    start_dt = parse_time(start)
    end_dt = parse_time(end)
    if start_dt is None or end_dt is None or end_dt <= start_dt:
        return None
    return round((end_dt - start_dt).total_seconds() / 60.0, 3)


def measurement_age_minutes(end: Any, captured_at: datetime) -> float | None:
    end_dt = parse_time(end)
    if end_dt is None:
        return None
    age = (captured_at - end_dt).total_seconds() / 60.0
    return round(max(0.0, age), 3)


def game_position(east: float, north: float) -> list[float]:
    return [round(east - ORIGIN_E, 3), round(-(north - ORIGIN_N), 3)]


def feature_properties(feature: Any) -> dict[str, Any]:
    if not isinstance(feature, dict):
        return {}
    props = feature.get("properties")
    return props if isinstance(props, dict) else {}


def traverse_name(feature: Any) -> str:
    props = feature_properties(feature)
    for key in ("traverse_name", "name", "featureID", "feature_id"):
        value = props.get(key)
        if value not in (None, ""):
            return str(value)
    return ""


def description(props: dict[str, Any]) -> str:
    for key in ("descr_fr", "descr_nl", "descr_en", "descr", "description"):
        value = props.get(key)
        if value not in (None, ""):
            return str(value)
    return ""


def point_coordinates(feature: Any) -> tuple[float, float] | None:
    if not isinstance(feature, dict):
        return None
    geometry = feature.get("geometry")
    if not isinstance(geometry, dict) or geometry.get("type") != "Point":
        return None
    coordinates = geometry.get("coordinates")
    if not isinstance(coordinates, list) or len(coordinates) < 2:
        return None
    east = as_float(coordinates[0])
    north = as_float(coordinates[1])
    if east is None or north is None:
        return None
    return east, north


def geojson_features(document: Any) -> list[dict[str, Any]]:
    if not isinstance(document, dict) or not isinstance(document.get("features"), list):
        return []
    return [feature for feature in document["features"] if isinstance(feature, dict)]


def device_index(document: Any) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for feature in geojson_features(document):
        name = traverse_name(feature)
        if not name:
            continue
        props = feature_properties(feature)
        result[name] = {"description": description(props), "orientation_deg": as_float(props.get("orientation")), "number_of_lanes": as_int(props.get("number_of_lanes")), "detectors": list(props.get("detectors", [])) if isinstance(props.get("detectors"), list) else []}
    return result


def live_index(document: Any, interval_key: str = "1m") -> dict[str, dict[str, Any]]:
    if not isinstance(document, dict):
        return {}
    data = document.get("data")
    if not isinstance(data, dict):
        return {}
    result: dict[str, dict[str, Any]] = {}
    for name, raw in data.items():
        if not isinstance(raw, dict):
            continue
        results = raw.get("results")
        if not isinstance(results, dict):
            continue
        measurement = results.get(interval_key)
        if isinstance(measurement, dict):
            result[str(name)] = normalize_measurement(measurement)
    return result


def normalize_measurement(raw: dict[str, Any]) -> dict[str, Any]:
    count = as_float(raw.get("count"))
    occupancy = as_float(raw.get("occupancy"))
    start = raw.get("start_time", raw.get("from"))
    end = raw.get("end_time", raw.get("to"))
    window = duration_minutes(start, end)
    rate = round(count / window, 3) if count is not None and count >= 0.0 and window is not None and window > 0.0 else None
    return {"count": count, "occupancy_pct": occupancy, "from": None if start in (None, "-") else str(start), "to": None if end in (None, "-") else str(end), "duration_minutes": window, "vehicles_per_minute": rate}


def wfs_measurement(props: dict[str, Any], interval_key: str = "1m") -> dict[str, Any]:
    suffix = f"{interval_key}_a"
    return normalize_measurement({"count": props.get(f"count_{suffix}"), "occupancy": props.get(f"occupancy_{suffix}"), "start_time": props.get(f"start_time_{suffix}"), "end_time": props.get(f"end_time_{suffix}")})


def choose_measurement(api_measurement: dict[str, Any] | None, wfs_value: dict[str, Any]) -> tuple[dict[str, Any], str]:
    if api_measurement and api_measurement.get("count") is not None and api_measurement.get("to"):
        return dict(api_measurement), "counts_api"
    if wfs_value.get("count") is not None and wfs_value.get("to"):
        return dict(wfs_value), "wfs_live_geom"
    if api_measurement:
        return dict(api_measurement), "counts_api"
    return dict(wfs_value), "wfs_live_geom"


def quantile(values: list[float], fraction: float) -> float | None:
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
    return round(ordered[lower] + (ordered[upper] - ordered[lower]) * (index - lower), 3)


def build_snapshot(devices: Any, live: Any, geometry: Any, captured_at: datetime | None = None) -> dict[str, Any]:
    captured = (captured_at or datetime.now(timezone.utc)).astimezone(timezone.utc)
    devices_by_name = device_index(devices)
    live_by_name = live_index(live, "1m")
    sensors: list[dict[str, Any]] = []

    for feature in geojson_features(geometry):
        name = traverse_name(feature)
        point = point_coordinates(feature)
        if not name or point is None:
            continue
        props = feature_properties(feature)
        device = devices_by_name.get(name, {})
        measurement, measurement_source = choose_measurement(live_by_name.get(name), wfs_measurement(props, "1m"))
        age = measurement_age_minutes(measurement.get("to"), captured)
        fresh = bool(measurement.get("count") is not None and measurement.get("duration_minutes") is not None and age is not None and age <= FRESH_MAX_AGE_MINUTES)
        measurement["age_minutes_at_capture"] = age
        measurement["fresh"] = fresh
        measurement["source"] = measurement_source
        east, north = point
        lanes = device.get("number_of_lanes")
        if lanes is None:
            lanes = as_int(props.get("num_lanes"))
        sensors.append({"id": name, "description": device.get("description") or description(props), "orientation_deg": device.get("orientation_deg") if device.get("orientation_deg") is not None else as_float(props.get("orientation")), "number_of_lanes": lanes, "active": bool(as_int(props.get("is_active")) == 1), "lambert72": [round(east, 3), round(north, 3)], "game": game_position(east, north), "measurement": measurement})

    measured = [sensor for sensor in sensors if sensor["measurement"].get("count") is not None]
    fresh = [sensor for sensor in sensors if bool(sensor.get("active", False)) and bool(sensor["measurement"].get("fresh"))]
    rates = [float(sensor["measurement"]["vehicles_per_minute"]) for sensor in fresh if sensor["measurement"].get("vehicles_per_minute") is not None]
    occupancies = [float(sensor["measurement"]["occupancy_pct"]) for sensor in fresh if sensor["measurement"].get("occupancy_pct") is not None and float(sensor["measurement"]["occupancy_pct"]) >= 0.0]

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
            "measurement_interval": "1m",
            "fresh_max_age_minutes": FRESH_MAX_AGE_MINUTES,
            "notes": [
                "Calibration aggregates use only fresh measurements from sensors marked active by official geometry.",
                "Vehicle rates are derived from the explicit source measurement window.",
                "Detector speed values are deliberately excluded because they are not calibrated for absolute speed compliance.",
            ],
        },
        "coordinate_system": {"source_crs": "EPSG:31370", "origin_e": ORIGIN_E, "origin_n": ORIGIN_N, "axes": "X=east, Y=up, Z=south", "units": "metres"},
        "raw_sha256": {"devices": sha256_json(devices), "live": sha256_json(live), "geometry": sha256_json(geometry)},
        "stats": {
            "geometry_sensor_count": len(sensors),
            "measured_sensor_count": len(measured),
            "fresh_measured_sensor_count": len(fresh),
            "fresh_rate_median_vehicles_per_minute": None if not rates else round(statistics.median(rates), 3),
            "fresh_rate_p25": quantile(rates, 0.25),
            "fresh_rate_p75": quantile(rates, 0.75),
            "fresh_occupancy_median_pct": None if not occupancies else round(statistics.median(occupancies), 3),
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
    parser.add_argument("--min-fresh-measured-sensors", type=int, default=1)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    devices = load_or_fetch(args.devices_file, DEVICES_URL)
    live = load_or_fetch(args.live_file, LIVE_URL)
    geometry = load_or_fetch(args.geometry_file, WFS_URL)
    snapshot = build_snapshot(devices, live, geometry)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(snapshot, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    stats = snapshot["stats"]
    if int(stats["geometry_sensor_count"]) < args.min_geometry_sensors:
        raise SystemExit(f"Brussels Mobility geometry gate failed: {stats['geometry_sensor_count']} < {args.min_geometry_sensors}")
    if int(stats["fresh_measured_sensor_count"]) < args.min_fresh_measured_sensors:
        raise SystemExit("Brussels Mobility fresh-live gate failed: %s < %s" % (stats["fresh_measured_sensor_count"], args.min_fresh_measured_sensors))
    print("BRUSSELS_MOBILITY_TRAFFIC_SNAPSHOT_OK: %d sensors, %d fresh live, median %.3f veh/min -> %s" % (stats["geometry_sensor_count"], stats["fresh_measured_sensor_count"], float(stats["fresh_rate_median_vehicles_per_minute"] or 0.0), args.output))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
