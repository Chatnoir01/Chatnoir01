#!/usr/bin/env python3
"""Fail-closed canonical identity check for registered road destination cells.

This verifier is evidence-only. It binds the redundant grid_cell_id carried by the
road readiness catalog to the exact canonical cell_id and EPSG:31370 bbox. It does
not authorize runtime mounting, rendering, collision, safe spawn, or JOUABLE.
"""
from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

CELL_ID_RE = re.compile(r"^bxl-e(-?\d+)-n(-?\d+)-s(\d+)$")
EXPECTED_CRS = "EPSG:31370"


def fail(message: str) -> None:
    raise SystemExit(f"ROAD_CELL_GRID_IDENTITY_FAIL: {message}")


def _number(value: Any, label: str) -> float:
    if isinstance(value, bool):
        fail(f"invalid {label}")
    try:
        number = float(value)
    except (TypeError, ValueError):
        fail(f"invalid {label}")
    if not number.is_integer():
        fail(f"non-integral {label}")
    return number


def _road_id(value: Any) -> int:
    # OSM IDs are canonical JSON integers. Never normalize booleans, numeric
    # strings, floats, or other coercible values into an identity.
    if type(value) is not int or value <= 0:
        fail("invalid road identity")
    return value


def validate_destination(destination: dict[str, Any]) -> tuple[str, str]:
    road_id = _road_id(destination.get("road_osm_id"))
    if destination.get("destination_id") != f"road-{road_id}":
        fail(f"destination identity drift {road_id}")
    if destination.get("readiness") != "REGISTERED_NOT_RENDERED":
        fail(f"readiness drift {road_id}")
    if destination.get("cell_crs") != EXPECTED_CRS:
        fail(f"cell CRS drift {road_id}")

    cell_id = str(destination.get("cell_id") or "")
    match = CELL_ID_RE.fullmatch(cell_id)
    if match is None:
        fail(f"invalid canonical cell id {road_id}")
    east = int(match.group(1))
    north = int(match.group(2))
    size = int(match.group(3))
    if size <= 0:
        fail(f"invalid canonical cell size {road_id}")

    bbox = destination.get("cell_bbox")
    if not isinstance(bbox, list) or len(bbox) != 4:
        fail(f"invalid cell bbox {road_id}")
    actual_bbox = [_number(value, f"cell bbox {road_id}") for value in bbox]
    expected_bbox = [float(east), float(north), float(east + size), float(north + size)]
    if actual_bbox != expected_bbox:
        fail(f"cell bbox identity drift {road_id}")

    expected_grid = f"E{east}_N{north}"
    grid_cell_id = str(destination.get("grid_cell_id") or "")
    if grid_cell_id != expected_grid:
        fail(f"grid cell identity drift {road_id}: stored={grid_cell_id} expected={expected_grid}")
    return cell_id, grid_cell_id


def validate_readiness(readiness: dict[str, Any]) -> dict[str, int]:
    destinations = readiness.get("destinations")
    if not isinstance(destinations, list):
        fail("destinations must be a list")
    if int(readiness.get("destination_count", -1)) != len(destinations):
        fail("destination accounting drift")

    road_ids: set[int] = set()
    cells: set[str] = set()
    grid_cells: dict[str, str] = {}
    for raw in destinations:
        if not isinstance(raw, dict):
            fail("malformed destination")
        road_id = _road_id(raw.get("road_osm_id"))
        if road_id in road_ids:
            fail(f"duplicate road identity {road_id}")
        road_ids.add(road_id)
        cell_id, grid_cell_id = validate_destination(raw)
        previous = grid_cells.get(grid_cell_id)
        if previous is not None and previous != cell_id:
            fail(f"grid alias collision {grid_cell_id}: {previous} vs {cell_id}")
        grid_cells[grid_cell_id] = cell_id
        cells.add(cell_id)

    return {"destination_count": len(destinations), "mapped_cell_count": len(cells)}


def main() -> int:
    path = Path("data/provenance/brussels_road_destination_readiness_catalog.json")
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        fail("readiness root must be object")
    result = validate_readiness(payload)
    print(
        "ROAD_CELL_GRID_IDENTITY_OK "
        f"destinations={result['destination_count']} mapped_cells={result['mapped_cell_count']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
