#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def load_transform():
    path = ROOT / "transform_osm_to_game.py"
    spec = importlib.util.spec_from_file_location("transform_osm_to_game", path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


transform = load_transform()


def road(osm_id: int, tags: dict[str, str]) -> dict[str, object]:
    return {
        "type": "way",
        "id": osm_id,
        "tags": tags,
        "geometry": [
            {"lat": 50.8419, "lon": 4.3480},
            {"lat": 50.8420, "lon": 4.3481},
        ],
    }


def drivable_for(tags: dict[str, str]) -> bool:
    converted = transform.convert({"elements": [road(1001, tags)]}, transform.DEFAULT_ORIGIN)
    assert len(converted["roads"]) == 1
    return bool(converted["roads"][0]["drivable"])


def test_unambiguous_motor_vehicle_access_no_is_not_drivable() -> None:
    assert drivable_for({"highway": "residential", "access": "no"}) is False
    assert drivable_for({"highway": "residential", "vehicle": "no"}) is False
    assert drivable_for({"highway": "residential", "motor_vehicle": "no"}) is False
    assert drivable_for({"highway": "residential", "motorcar": "no"}) is False


def test_more_specific_access_override_wins() -> None:
    assert drivable_for({"highway": "residential", "access": "no", "motor_vehicle": "yes"}) is True
    assert drivable_for({"highway": "residential", "vehicle": "no", "motor_vehicle": "yes"}) is True
    assert drivable_for({"highway": "residential", "motor_vehicle": "no", "motorcar": "yes"}) is True


def test_unrestricted_supported_road_stays_drivable() -> None:
    assert drivable_for({"highway": "residential"}) is True


if __name__ == "__main__":
    test_unambiguous_motor_vehicle_access_no_is_not_drivable()
    test_more_specific_access_override_wins()
    test_unrestricted_supported_road_stays_drivable()
    print("OSM_DRIVABLE_ACCESS_SEMANTICS_OK: hierarchy-aware explicit access=no restrictions are excluded from drivable roads")
