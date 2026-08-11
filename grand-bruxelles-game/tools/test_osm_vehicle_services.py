#!/usr/bin/env python3
"""Self-contained test for OSM vehicle-service extraction."""

from __future__ import annotations

import importlib.util
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("vehicle_services", HERE / "extract_osm_vehicle_services.py")
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def main() -> int:
    raw = {
        "elements": [
            {
                "type": "node",
                "id": 101,
                "lat": 50.8419,
                "lon": 4.3480,
                "tags": {
                    "shop": "car_repair",
                    "name": "Garage Test",
                    "opening_hours": "Mo-Fr 08:00-18:00",
                    "addr:street": "Rue Test",
                    "addr:housenumber": "12",
                },
            },
            {
                "type": "way",
                "id": 202,
                "tags": {"shop": "tyres", "name": "Pneus Test"},
                "geometry": [
                    {"lat": 50.8420, "lon": 4.3481},
                    {"lat": 50.8420, "lon": 4.3483},
                    {"lat": 50.8422, "lon": 4.3483},
                    {"lat": 50.8422, "lon": 4.3481},
                    {"lat": 50.8420, "lon": 4.3481},
                ],
            },
            {
                "type": "node",
                "id": 303,
                "lat": 50.8421,
                "lon": 4.3482,
                "tags": {"shop": "car", "name": "Dealer ignored"},
            },
        ]
    }

    data = MODULE.convert(raw)
    assert data["format"] == "grand-bruxelles-vehicle-services-v1"
    assert data["license"] == "ODbL-1.0"
    assert data["stats"] == {"services": 2, "garages": 1, "tyre_services": 1, "named": 2}, data["stats"]
    assert [item["kind"] for item in data["services"]] == ["garage", "tyres"]
    garage = data["services"][0]
    assert garage["name"] == "Garage Test"
    assert garage["street"] == "Rue Test" and garage["housenumber"] == "12"
    assert abs(float(garage["point"][0])) < 0.01 and abs(float(garage["point"][1])) < 0.01, garage["point"]
    tyre = data["services"][1]
    assert tyre["osm_type"] == "way"
    assert len(tyre["point"]) == 2
    assert all(item["name"] != "Dealer ignored" for item in data["services"])
    print("OSM_VEHICLE_SERVICES_TEST_OK:", data["stats"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
