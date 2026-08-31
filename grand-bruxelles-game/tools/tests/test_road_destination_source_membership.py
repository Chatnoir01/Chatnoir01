#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VALIDATOR = ROOT / "tools" / "validate_road_destination_source_membership.py"
READINESS = ROOT / "data" / "provenance" / "brussels_road_destination_readiness_catalog.json"
SOURCE = ROOT / "data" / "osm" / "vertical_slice_01.game.json"

spec = importlib.util.spec_from_file_location("road_source_membership", VALIDATOR)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def test_real_catalog_road_ids_are_source_members() -> None:
    readiness = json.loads(READINESS.read_text(encoding="utf-8"))
    source = json.loads(SOURCE.read_text(encoding="utf-8"))
    result = module.validate_source_membership(readiness, source)
    assert result["destination_count"] == 96
    assert result["source_road_count"] == 140


def test_forged_but_self_consistent_road_id_fails_closed() -> None:
    readiness = json.loads(READINESS.read_text(encoding="utf-8"))
    source = json.loads(SOURCE.read_text(encoding="utf-8"))
    destination = readiness["destinations"][0]
    forged = 999_999_999_999
    assert all(road.get("osm_id") != forged for road in source["roads"])
    destination["road_osm_id"] = forged
    destination["destination_id"] = f"road-{forged}"
    try:
        module.validate_source_membership(readiness, source)
    except SystemExit as exc:
        assert "road source membership drift" in str(exc)
    else:
        raise AssertionError("self-consistent forged road identity bypassed source membership")


def test_non_drivable_source_road_cannot_back_destination() -> None:
    readiness = json.loads(READINESS.read_text(encoding="utf-8"))
    source = json.loads(SOURCE.read_text(encoding="utf-8"))
    destination = readiness["destinations"][0]
    road_id = destination["road_osm_id"]
    source_road = next(road for road in source["roads"] if road.get("osm_id") == road_id)
    source_road["drivable"] = False
    try:
        module.validate_source_membership(readiness, source)
    except SystemExit as exc:
        assert "road source drivability drift" in str(exc)
    else:
        raise AssertionError("non-drivable source road remained destination-eligible")


if __name__ == "__main__":
    test_real_catalog_road_ids_are_source_members()
    test_forged_but_self_consistent_road_id_fails_closed()
    test_non_drivable_source_road_cannot_back_destination()
    print("ROAD_DESTINATION_SOURCE_MEMBERSHIP_TEST_OK")
