#!/usr/bin/env python3
"""Fail-closed canonical identity check for registered road destination cells.

This verifier is evidence-only. It binds the redundant grid_cell_id carried by the
road readiness catalog to the exact canonical cell_id and EPSG:31370 bbox, locks
each destination to the canonical source provenance, and proves that the catalog
remains on the existing closed authorization rails. It does not authorize runtime
mounting, rendering, collision, safe spawn, or JOUABLE.
"""
from __future__ import annotations

import json
import math
import re
from pathlib import Path
from typing import Any

CELL_ID_RE = re.compile(r"^bxl-e(-?\d+)-n(-?\d+)-s(\d+)$")
EXPECTED_CRS = "EPSG:31370"
EXPECTED_SOURCE_PATH = "data/osm/vertical_slice_01.game.json"
EXPECTED_SOURCE_PROVIDER = "OpenStreetMap contributors via Overpass API"
EXPECTED_SOURCE_LICENSE = "ODbL-1.0"
EXPECTED_SOURCE_SHA256 = "899bc73ee0eea3623d7cc45455a542c1704039ef0239c13c33b3c74b4a241398"
ROOT_AUTHORIZATION_RAILS = frozenset(
    {
        "collision_authorized",
        "jouable_authorized",
        "render_authorized",
        "road_cell_mapping_authorized",
        "runtime_directory_scan_authorized",
        "runtime_mount_authorized",
        "safe_spawn_authorized",
    }
)
DESTINATION_AUTHORIZATION_RAILS = frozenset(
    {
        "collision_authorized",
        "jouable_authorized",
        "render_authorized",
        "runtime_mount_authorized",
        "safe_spawn_authorized",
    }
)
EXPECTED_DESTINATION_PROVENANCE = {
    "source_path": EXPECTED_SOURCE_PATH,
    "source_provider": EXPECTED_SOURCE_PROVIDER,
    "source_license": EXPECTED_SOURCE_LICENSE,
    "source_sha256": EXPECTED_SOURCE_SHA256,
}


def fail(message: str) -> None:
    raise SystemExit(f"ROAD_CELL_GRID_IDENTITY_FAIL: {message}")


def _number(value: Any, label: str) -> float:
    if type(value) not in (int, float):
        fail(f"invalid {label}")
    number = float(value)
    if not math.isfinite(number):
        fail(f"invalid {label}")
    if not number.is_integer():
        fail(f"non-integral {label}")
    return number


def _road_id(value: Any) -> int:
    if type(value) is not int or value <= 0:
        fail("invalid road identity")
    return value


def _require_closed_authorization(
    payload: Any,
    expected_keys: frozenset[str],
    label: str,
) -> None:
    if not isinstance(payload, dict):
        fail(f"{label} authorization rail drift: object required")
    actual_keys = frozenset(payload)
    if actual_keys != expected_keys:
        missing = sorted(expected_keys - actual_keys)
        unknown = sorted(actual_keys - expected_keys)
        fail(f"{label} authorization rail drift: missing={missing} unknown={unknown}")
    for key in sorted(expected_keys):
        if payload.get(key) is not False:
            fail(f"{label} authorization rail drift: {key} must remain false")


def _require_no_unknown_boolean_controls(
    payload: dict[str, Any],
    known_boolean_keys: frozenset[str],
    label: str,
    skipped_direct_objects: frozenset[str] = frozenset(),
) -> None:
    """Reject boolean aliases outside canonical control-plane rails, recursively.

    Direct ``*_authorized`` fields are intentionally left to the exact authorization
    validator so added top-level rail keys retain the stronger rail-drift diagnostic.
    Canonical nested authorization objects may be skipped explicitly because they are
    validated separately. Any boolean hidden deeper in otherwise extensible metadata,
    including nested ``*_authorized`` aliases, is control-bearing and fails closed.
    """
    unknown: list[str] = []

    def walk(value: Any, path: str, depth: int) -> None:
        if isinstance(value, dict):
            for key, child in value.items():
                child_path = f"{path}.{key}" if path else key
                if depth == 0 and key in skipped_direct_objects:
                    continue
                if type(child) is bool:
                    if depth == 0 and (
                        key in known_boolean_keys or key.endswith("_authorized")
                    ):
                        continue
                    unknown.append(child_path)
                    continue
                walk(child, child_path, depth + 1)
        elif isinstance(value, list):
            for index, child in enumerate(value):
                child_path = f"{path}[{index}]" if path else f"[{index}]"
                walk(child, child_path, depth + 1)

    walk(payload, "", 0)
    if unknown:
        fail(f"{label} unknown boolean control field(s): {sorted(unknown)}")


def _require_destination_provenance(destination: dict[str, Any], road_id: int) -> None:
    for field, expected in EXPECTED_DESTINATION_PROVENANCE.items():
        actual = destination.get(field)
        if actual != expected:
            fail(
                "destination source provenance drift "
                f"{road_id}: {field} stored={actual!r} expected={expected!r}"
            )


def validate_destination(destination: dict[str, Any]) -> tuple[str, str]:
    road_id = _road_id(destination.get("road_osm_id"))
    if destination.get("destination_id") != f"road-{road_id}":
        fail(f"destination identity drift {road_id}")
    if destination.get("readiness") != "REGISTERED_NOT_RENDERED":
        fail(f"readiness drift {road_id}")
    if destination.get("cell_crs") != EXPECTED_CRS:
        fail(f"cell CRS drift {road_id}")
    _require_destination_provenance(destination, road_id)

    _require_no_unknown_boolean_controls(
        destination,
        DESTINATION_AUTHORIZATION_RAILS,
        "destination",
    )
    destination_authorization = {
        key: value
        for key, value in destination.items()
        if key.endswith("_authorized")
    }
    _require_closed_authorization(
        destination_authorization,
        DESTINATION_AUTHORIZATION_RAILS,
        "destination",
    )

    cell_id = str(destination.get("cell_id") or "")
    match = CELL_ID_RE.fullmatch(cell_id)
    if match is None:
        fail(f"invalid canonical cell id {road_id}")
    east = int(match.group(1))
    north = int(match.group(2))
    size = int(match.group(3))
    if size <= 0:
        fail(f"invalid canonical cell size {road_id}")
    canonical_cell_id = f"bxl-e{east}-n{north}-s{size}"
    if cell_id != canonical_cell_id:
        fail(f"non-canonical cell id {road_id}: stored={cell_id} expected={canonical_cell_id}")

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
    _require_no_unknown_boolean_controls(
        readiness,
        frozenset(),
        "readiness root",
        skipped_direct_objects=frozenset({"authorization", "destinations"}),
    )
    if readiness.get("corrected_frame_source_sha256") != EXPECTED_SOURCE_SHA256:
        fail(
            "catalog source provenance drift: corrected_frame_source_sha256 "
            f"stored={readiness.get('corrected_frame_source_sha256')!r} "
            f"expected={EXPECTED_SOURCE_SHA256!r}"
        )
    _require_closed_authorization(
        readiness.get("authorization"),
        ROOT_AUTHORIZATION_RAILS,
        "authorization",
    )

    destinations = readiness.get("destinations")
    if not isinstance(destinations, list):
        fail("destinations must be a list")
    destination_count = readiness.get("destination_count")
    if type(destination_count) is not int or destination_count != len(destinations):
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
