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


def main() -> int:
    devices = {
        "devices": {
            "DEL_103_6": {
                "descr": "Synthetic Brussels counter",
                "orientation": 135,
                "number_of_lanes": 2,
                "detectors": ["DEL_103_6.1", "DEL_103_6.2"],
            },
            "DEL_200_1": {
                "descr": "Second counter",
                "orientation": 270,
                "number_of_lanes": 1,
            },
        }
    }
    live = {
        "live": {
            "DEL_103_6": {
                "t1": {
                    "count": 87,
                    "occupancy": 19.5,
                    "speed": 41.2,
                    "from": "2026-08-12T06:00:00+00:00",
                    "to": "2026-08-12T07:00:00+00:00",
                }
            },
            "DEL_200_1": {
                "latest": {
                    "count": 31,
                    "occupancy": 8.0,
                    "from": "2026-08-12T06:45:00Z",
                    "to": "2026-08-12T07:00:00Z",
                }
            },
        }
    }
    geometry = {
        "type": "FeatureCollection",
        "features": [
            {
                "type": "Feature",
                "id": "traffic_live_geom.DEL_103_6",
                "properties": {"name": "DEL_103_6"},
                "geometry": {
                    "type": "Point",
                    "coordinates": [module.ORIGIN_E + 100.0, module.ORIGIN_N - 50.0],
                },
            },
            {
                "type": "Feature",
                "id": "traffic_live_geom.DEL_200_1",
                "properties": {"name": "DEL_200_1"},
                "geometry": {
                    "type": "Point",
                    "coordinates": [module.ORIGIN_E - 25.0, module.ORIGIN_N + 75.0],
                },
            },
        ],
    }

    snapshot = module.build_snapshot(
        devices,
        live,
        geometry,
        datetime(2026, 8, 12, 7, 1, tzinfo=timezone.utc),
    )

    assert snapshot["format"] == module.FORMAT
    assert snapshot["source"]["license"] == "CC0-1.0"
    assert snapshot["source"]["geometry_crs"] == "EPSG:31370"
    assert snapshot["stats"]["geometry_sensor_count"] == 2
    assert snapshot["stats"]["measured_sensor_count"] == 2
    assert snapshot["stats"]["count_median"] == 59.0
    assert len(snapshot["raw_sha256"]["live"]) == 64

    first = snapshot["sensors"][0]
    assert first["id"] == "DEL_103_6"
    assert first["description"] == "Synthetic Brussels counter"
    assert first["number_of_lanes"] == 2
    assert first["game"] == [100.0, 50.0]
    assert first["measurement"]["count"] == 87.0
    assert first["measurement"]["occupancy_pct"] == 19.5
    assert first["measurement"]["duration_minutes"] == 60.0
    # Speed must never leak into the calibrated sensor representation.
    assert "speed" not in first["measurement"]

    second = snapshot["sensors"][1]
    assert second["game"] == [-25.0, -75.0]
    assert second["measurement"]["duration_minutes"] == 15.0

    print("BRUSSELS_MOBILITY_TRAFFIC_SNAPSHOT_TEST_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
