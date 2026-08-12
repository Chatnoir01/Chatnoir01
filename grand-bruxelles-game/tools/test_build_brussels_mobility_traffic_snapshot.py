#!/usr/bin/env python3
"""Offline regression test for the Brussels Mobility traffic snapshot builder."""

from __future__ import annotations

import importlib.util
from datetime import datetime, timezone
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("build_brussels_mobility_traffic_snapshot.py")
spec = importlib.util.spec_from_file_location("bm_snapshot", MODULE_PATH)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def _device(name: str, description: str, orientation: int, lanes: int) -> dict:
    return {
        "type": "Feature",
        "id": "traverse.synthetic",
        "geometry": {"type": "Point", "coordinates": [4.35, 50.84]},
        "properties": {
            "traverse_name": name,
            "descr_fr": description,
            "orientation": orientation,
            "number_of_lanes": lanes,
            "detectors": [f"{name}_1"],
        },
    }


def _geometry(name: str, east: float, north: float, *, active: int, count: float | None, occupancy: float | None, start: str | None, end: str | None) -> dict:
    return {
        "type": "Feature",
        "id": "traffic_live_geom.synthetic",
        "geometry": {"type": "Point", "coordinates": [east, north]},
        "properties": {
            "traverse_name": name,
            "descr_fr": f"WFS {name}",
            "num_lanes": 2,
            "orientation": 180,
            "is_active": active,
            "count_1m_a": count,
            "occupancy_1m_a": occupancy,
            "speed_1m_a": 999.0,
            "start_time_1m_a": start,
            "end_time_1m_a": end,
        },
    }


def main() -> int:
    captured_at = datetime(2026, 8, 12, 7, 10, tzinfo=timezone.utc)
    devices = {
        "requestDate": "2026/08/12 09:10:00",
        "type": "FeatureCollection",
        "totalFeatures": 4,
        "features": [
            _device("MAD_103", "Synthetic fresh API counter", 260, 2),
            _device("MAD_203", "Synthetic WFS fallback counter", 80, 1),
            _device("STE_TD3", "Synthetic stale counter", 100, 2),
            _device("OFF_001", "Synthetic fresh but inactive counter", 140, 2),
        ],
    }
    live = {
        "requestDate": "2026/08/12 09:10:00",
        "data": {
            "MAD_103": {"results": {"1m": {"count": 36, "speed": 39.5, "occupancy": 27.5, "start_time": "2026-08-12T07:08:00Z", "end_time": "2026-08-12T07:09:00Z"}}},
            "MAD_203": {"results": {"1m": {"count": None, "speed": None, "occupancy": None, "start_time": "-", "end_time": "-"}}},
            "STE_TD3": {"results": {"1m": {"count": 8, "speed": 82.0, "occupancy": 24.0, "start_time": "2025-10-16T12:55:00Z", "end_time": "2025-10-16T12:56:00Z"}}},
            "OFF_001": {"results": {"1m": {"count": 90, "speed": 28.0, "occupancy": 70.0, "start_time": "2026-08-12T07:08:00Z", "end_time": "2026-08-12T07:09:00Z"}}},
        },
    }
    geometry = {
        "type": "FeatureCollection",
        "features": [
            _geometry("MAD_103", module.ORIGIN_E + 100.0, module.ORIGIN_N - 50.0, active=1, count=35, occupancy=26.0, start="2026-08-12T07:08:00Z", end="2026-08-12T07:09:00Z"),
            _geometry("MAD_203", module.ORIGIN_E - 25.0, module.ORIGIN_N + 75.0, active=1, count=37, occupancy=22.0, start="2026-08-12T07:08:00Z", end="2026-08-12T07:09:00Z"),
            _geometry("STE_TD3", module.ORIGIN_E + 12.0, module.ORIGIN_N + 18.0, active=0, count=8, occupancy=24.0, start="2025-10-16T12:55:00Z", end="2025-10-16T12:56:00Z"),
            _geometry("OFF_001", module.ORIGIN_E + 20.0, module.ORIGIN_N - 10.0, active=0, count=90, occupancy=70.0, start="2026-08-12T07:08:00Z", end="2026-08-12T07:09:00Z"),
        ],
    }

    snapshot = module.build_snapshot(devices, live, geometry, captured_at)

    assert snapshot["format"] == module.FORMAT
    assert snapshot["source"]["license"] == "CC0-1.0"
    assert snapshot["source"]["geometry_crs"] == "EPSG:31370"
    assert snapshot["source"]["measurement_interval"] == "1m"
    assert snapshot["stats"]["geometry_sensor_count"] == 4
    assert snapshot["stats"]["measured_sensor_count"] == 4
    assert snapshot["stats"]["fresh_measured_sensor_count"] == 2
    assert snapshot["stats"]["fresh_rate_median_vehicles_per_minute"] == 36.5
    assert len(snapshot["raw_sha256"]["live"]) == 64

    first = snapshot["sensors"][0]
    assert first["id"] == "MAD_103"
    assert first["description"] == "Synthetic fresh API counter"
    assert first["number_of_lanes"] == 2
    assert first["game"] == [100.0, 50.0]
    assert first["active"] is True
    assert first["measurement"]["count"] == 36.0
    assert first["measurement"]["occupancy_pct"] == 27.5
    assert first["measurement"]["duration_minutes"] == 1.0
    assert first["measurement"]["vehicles_per_minute"] == 36.0
    assert first["measurement"]["age_minutes_at_capture"] == 1.0
    assert first["measurement"]["fresh"] is True
    assert first["measurement"]["source"] == "counts_api"
    assert "speed" not in first["measurement"]

    second = snapshot["sensors"][1]
    assert second["game"] == [-25.0, -75.0]
    assert second["number_of_lanes"] == 1
    assert second["measurement"]["count"] == 37.0
    assert second["measurement"]["source"] == "wfs_live_geom"
    assert second["measurement"]["fresh"] is True

    stale = snapshot["sensors"][2]
    assert stale["measurement"]["count"] == 8.0
    assert stale["measurement"]["fresh"] is False
    assert stale["measurement"]["age_minutes_at_capture"] > module.FRESH_MAX_AGE_MINUTES
    assert "speed" not in stale["measurement"]

    inactive_fresh = snapshot["sensors"][3]
    assert inactive_fresh["active"] is False
    assert inactive_fresh["measurement"]["fresh"] is True
    assert inactive_fresh["measurement"]["vehicles_per_minute"] == 90.0

    print("BRUSSELS_MOBILITY_TRAFFIC_SNAPSHOT_TEST_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
