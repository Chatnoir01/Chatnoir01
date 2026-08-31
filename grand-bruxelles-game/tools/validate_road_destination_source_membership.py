#!/usr/bin/env python3
"""Fail-closed source membership for automatic ``road-<OSM id>`` destinations.

This gate proves only that each registered destination identity resolves to a real,
drivable road in the pinned corridor OSM payload. It does not authorize rendering,
collision, runtime mounting, safe spawn, or JOUABLE promotion.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

EXPECTED_SOURCE_FORMAT = "grand-bruxelles-osm-v1"
EXPECTED_SOURCE_PROVIDER = "OpenStreetMap contributors via Overpass API"
EXPECTED_SOURCE_LICENSE = "ODbL-1.0"


def fail(message: str) -> None:
    raise SystemExit(f"ROAD_DESTINATION_SOURCE_MEMBERSHIP_FAIL: {message}")


def _positive_int(value: Any, label: str) -> int:
    if type(value) is not int or value <= 0:
        fail(f"invalid {label}")
    return value


def _source_road_index(source: dict[str, Any]) -> dict[int, dict[str, Any]]:
    if source.get("format") != EXPECTED_SOURCE_FORMAT:
        fail("source format drift")
    if source.get("source") != EXPECTED_SOURCE_PROVIDER:
        fail("source provider drift")
    if source.get("license") != EXPECTED_SOURCE_LICENSE:
        fail("source license drift")

    roads = source.get("roads")
    if not isinstance(roads, list):
        fail("source roads must be a list")

    index: dict[int, dict[str, Any]] = {}
    for raw in roads:
        if not isinstance(raw, dict):
            fail("malformed source road")
        road_id = _positive_int(raw.get("osm_id"), "source road identity")
        if road_id in index:
            fail(f"duplicate source road identity {road_id}")
        if type(raw.get("drivable")) is not bool:
            fail(f"invalid source road drivability {road_id}")
        index[road_id] = raw
    return index


def validate_source_membership(
    readiness: dict[str, Any],
    source: dict[str, Any],
) -> dict[str, int]:
    if not isinstance(readiness, dict):
        fail("readiness root must be object")
    if not isinstance(source, dict):
        fail("source root must be object")

    source_roads = _source_road_index(source)
    destinations = readiness.get("destinations")
    if not isinstance(destinations, list):
        fail("destinations must be a list")

    seen: set[int] = set()
    for raw in destinations:
        if not isinstance(raw, dict):
            fail("malformed destination")
        road_id = _positive_int(raw.get("road_osm_id"), "destination road identity")
        if raw.get("destination_id") != f"road-{road_id}":
            fail(f"destination identity drift {road_id}")
        if road_id in seen:
            fail(f"duplicate destination road identity {road_id}")
        seen.add(road_id)

        source_road = source_roads.get(road_id)
        if source_road is None:
            fail(f"road source membership drift {road_id}: missing from pinned source")
        if source_road.get("drivable") is not True:
            fail(f"road source drivability drift {road_id}: source road is not drivable")

    return {
        "destination_count": len(destinations),
        "source_road_count": len(source_roads),
    }


def main() -> int:
    readiness_path = Path("data/provenance/brussels_road_destination_readiness_catalog.json")
    source_path = Path("data/osm/vertical_slice_01.game.json")
    readiness = json.loads(readiness_path.read_text(encoding="utf-8"))
    source = json.loads(source_path.read_text(encoding="utf-8"))
    result = validate_source_membership(readiness, source)
    print(
        "ROAD_DESTINATION_SOURCE_MEMBERSHIP_OK "
        f"destinations={result['destination_count']} source_roads={result['source_road_count']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
