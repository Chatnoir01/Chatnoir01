#!/usr/bin/env python3
"""Fail-close registered road destination semantics against exact pinned OSM source.

This gate is evidence-only. It does not authorize rendering, collision, runtime
mounting, safe spawn, or JOUABLE state.
"""
from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
READINESS_PATH = ROOT / "data/provenance/brussels_road_destination_readiness_catalog.json"
SOURCE_RELATIVE_PATH = "data/osm/vertical_slice_01.game.json"
SOURCE_PATH = ROOT / SOURCE_RELATIVE_PATH
EXPECTED_SOURCE_SHA256 = "899bc73ee0eea3623d7cc45455a542c1704039ef0239c13c33b3c74b4a241398"
EXPECTED_FORMAT = "grand-bruxelles-osm-v1"
EXPECTED_PROVIDER = "OpenStreetMap contributors via Overpass API"
EXPECTED_LICENSE = "ODbL-1.0"


def fail(message: str) -> None:
    raise SystemExit(f"ROAD_DESTINATION_SOURCE_SEMANTICS_FAIL: {message}")


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def _number(value: Any, label: str) -> float:
    if type(value) not in (int, float):
        fail(f"invalid {label}")
    number = float(value)
    if not math.isfinite(number):
        fail(f"invalid {label}")
    return number


def _points(raw: Any, road_id: int) -> list[list[float]]:
    if not isinstance(raw, list) or len(raw) < 2:
        fail(f"malformed source points {road_id}")
    result: list[list[float]] = []
    for index, pair in enumerate(raw):
        if not isinstance(pair, list) or len(pair) != 2:
            fail(f"malformed source point {road_id}[{index}]")
        result.append([
            _number(pair[0], f"source point {road_id}[{index}].x"),
            _number(pair[1], f"source point {road_id}[{index}].z"),
        ])
    return result


def _source_index() -> dict[int, dict[str, Any]]:
    try:
        source_bytes = SOURCE_PATH.read_bytes()
    except OSError as exc:
        fail(f"source file unavailable: {exc}")
    actual_sha = hashlib.sha256(source_bytes).hexdigest()
    if actual_sha != EXPECTED_SOURCE_SHA256:
        fail(f"source sha256 drift stored={EXPECTED_SOURCE_SHA256!r} actual={actual_sha!r}")
    try:
        source = json.loads(source_bytes.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        fail(f"source parse failure: {exc}")
    if not isinstance(source, dict):
        fail("source root must be object")
    if source.get("format") != EXPECTED_FORMAT:
        fail("source format drift")
    if source.get("source") != EXPECTED_PROVIDER:
        fail("source provider drift")
    if source.get("license") != EXPECTED_LICENSE:
        fail("source license drift")
    roads = source.get("roads")
    if not isinstance(roads, list):
        fail("source roads must be list")

    index: dict[int, dict[str, Any]] = {}
    for raw in roads:
        if not isinstance(raw, dict):
            fail("malformed source road")
        road_id = raw.get("osm_id")
        if type(road_id) is not int or road_id <= 0:
            fail("invalid source road identity")
        if road_id in index:
            fail(f"duplicate source road identity {road_id}")
        if raw.get("drivable") is not True:
            continue
        name = raw.get("name")
        road_class = raw.get("class")
        if type(name) is not str or not name:
            fail(f"invalid source road name {road_id}")
        if type(road_class) is not str:
            fail(f"invalid source road class {road_id}")
        width = _number(raw.get("width"), f"source road width {road_id}")
        if width <= 0.0:
            fail(f"non-positive source road width {road_id}")
        points = _points(raw.get("points"), road_id)
        xs = [pair[0] for pair in points]
        zs = [pair[1] for pair in points]
        index[road_id] = {
            "road_name": name,
            "road_class": road_class,
            "road_width_m": width,
            "source_local_point_count": len(points),
            "source_points_sha256": hashlib.sha256(canonical_json(points).encode("utf-8")).hexdigest(),
            "source_local_bbox": [min(xs), min(zs), max(xs), max(zs)],
        }
    return index


def _require_exact(destination: dict[str, Any], field: str, expected: Any, road_id: int) -> None:
    actual = destination.get(field)
    if actual != expected:
        fail(
            "destination source semantic drift "
            f"{road_id}: {field} stored={actual!r} expected={expected!r}"
        )


def validate_readiness(readiness: dict[str, Any]) -> dict[str, int]:
    if not isinstance(readiness, dict):
        fail("readiness root must be object")
    destinations = readiness.get("destinations")
    if not isinstance(destinations, list):
        fail("destinations must be list")
    source_index = _source_index()
    seen: set[int] = set()
    for raw in destinations:
        if not isinstance(raw, dict):
            fail("malformed destination")
        road_id = raw.get("road_osm_id")
        if type(road_id) is not int or road_id <= 0:
            fail("invalid destination road identity")
        if road_id in seen:
            fail(f"duplicate destination road identity {road_id}")
        seen.add(road_id)
        source_semantics = source_index.get(road_id)
        if source_semantics is None:
            fail(f"destination source membership drift {road_id}")
        for field, expected in source_semantics.items():
            _require_exact(raw, field, expected, road_id)
    return {"destination_count": len(destinations), "source_road_count": len(source_index)}


def main() -> int:
    try:
        readiness = json.loads(READINESS_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"readiness parse failure: {exc}")
    result = validate_readiness(readiness)
    print(
        "ROAD_DESTINATION_SOURCE_SEMANTICS_OK "
        f"destinations={result['destination_count']} source_roads={result['source_road_count']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
