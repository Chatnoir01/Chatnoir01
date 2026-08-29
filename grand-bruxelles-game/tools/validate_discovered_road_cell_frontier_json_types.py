#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

CELL_SIZE_M = 500
COUNT_FIELDS = (
    "source_zero_intersection_road_count",
    "candidate_cell_count",
    "covered_zero_intersection_road_count",
    "uncovered_zero_intersection_road_count",
    "registered_cell_overlap_count",
)


def fail(message: str) -> None:
    raise SystemExit(f"DISCOVERED_ROAD_CELL_FRONTIER_JSON_TYPES_FAIL: {message}")


def require_int(value: Any, label: str, *, minimum: int | None = None) -> int:
    if type(value) is not int:
        fail(f"{label} JSON type drift")
    if minimum is not None and value < minimum:
        fail(f"{label} value drift")
    return value


def require_int_list(value: Any, label: str, *, positive: bool = False) -> list[int]:
    if not isinstance(value, list):
        fail(f"{label} JSON type drift")
    minimum = 1 if positive else None
    for item in value:
        require_int(item, label, minimum=minimum)
    return value


def validate_frontier_json_types(frontier: dict[str, Any]) -> None:
    if not isinstance(frontier, dict):
        fail("frontier object drift")

    require_int(frontier.get("cell_size_m"), "cell_size_m")
    if frontier["cell_size_m"] != CELL_SIZE_M:
        fail("cell_size_m value drift")

    for field in COUNT_FIELDS:
        require_int(frontier.get(field), field, minimum=0)

    source_ids = require_int_list(
        frontier.get("source_zero_intersection_road_osm_ids"),
        "source road_osm_id",
        positive=True,
    )
    if source_ids != sorted(set(source_ids)):
        fail("source road_osm_id order/uniqueness drift")

    uncovered_ids = require_int_list(
        frontier.get("uncovered_zero_intersection_road_osm_ids"),
        "uncovered road_osm_id",
        positive=True,
    )
    if uncovered_ids != sorted(set(uncovered_ids)):
        fail("uncovered road_osm_id order/uniqueness drift")

    rows = frontier.get("candidate_cells")
    if not isinstance(rows, list):
        fail("candidate cells JSON type drift")
    if len(rows) != frontier["candidate_cell_count"]:
        fail("candidate cell accounting drift")

    for row in rows:
        if not isinstance(row, dict):
            fail("candidate cell object drift")
        require_int(row.get("cell_size_m"), "candidate cell_size_m")
        if row["cell_size_m"] != CELL_SIZE_M:
            fail("candidate cell_size_m value drift")

        bbox = require_int_list(row.get("bbox"), "candidate bbox")
        if len(bbox) != 4:
            fail("candidate bbox length drift")

        roads = require_int_list(row.get("road_osm_ids"), "candidate road_osm_id", positive=True)
        require_int(row.get("road_count"), "candidate road_count", minimum=0)
        if len(roads) != row["road_count"]:
            fail("candidate road accounting drift")
        if roads != sorted(set(roads)):
            fail("candidate road_osm_id order/uniqueness drift")

        if type(row.get("registered")) is not bool:
            fail("candidate registered JSON type drift")
        if type(row.get("source_registration_ready")) is not bool:
            fail("candidate source_registration_ready JSON type drift")


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise SystemExit(f"DISCOVERED_ROAD_CELL_FRONTIER_JSON_TYPES_FAIL: invalid JSON {path}") from exc
    if not isinstance(value, dict):
        fail("frontier object drift")
    return value


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("frontier", type=Path)
    args = parser.parse_args()
    validate_frontier_json_types(load_json(args.frontier))
    print("DISCOVERED_ROAD_CELL_FRONTIER_JSON_TYPES_GREEN")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
