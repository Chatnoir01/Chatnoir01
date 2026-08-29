#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

FORMAT = "grand-bruxelles-discovered-road-cell-coverage-frontier-v1"
TARGET_CRS = "EPSG:31370"
CELL_SIZE_M = 500
COUNT_FIELDS = (
    "source_zero_intersection_road_count",
    "candidate_cell_count",
    "covered_zero_intersection_road_count",
    "uncovered_zero_intersection_road_count",
    "registered_cell_overlap_count",
)
AUTHORIZATION_FIELDS = (
    "candidate_manifest_creation_authorized",
    "cell_registration_authorized",
    "municipality_inference_authorized",
    "road_cell_mapping_authorized",
    "runtime_mount_authorized",
    "render_authorized",
    "collision_authorized",
    "safe_spawn_authorized",
    "jouable_authorized",
)
TOP_LEVEL_FIELDS = {
    "format",
    "crs",
    "cell_size_m",
    "source_intersection_evidence_sha256",
    "source_zero_intersection_road_count",
    "source_zero_intersection_road_osm_ids",
    "candidate_cell_count",
    "candidate_cells",
    "covered_zero_intersection_road_count",
    "uncovered_zero_intersection_road_count",
    "uncovered_zero_intersection_road_osm_ids",
    "registered_cell_overlap_count",
    *AUTHORIZATION_FIELDS,
    "frontier_sha256",
}
CANDIDATE_FIELDS = {
    "cell_id",
    "crs",
    "bbox",
    "cell_size_m",
    "road_osm_ids",
    "road_count",
    "registered",
    "manifest_path",
    "source_registration_ready",
}


def fail(message: str) -> None:
    raise SystemExit(f"DISCOVERED_ROAD_CELL_FRONTIER_JSON_TYPES_FAIL: {message}")


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def sha256_json(value: Any) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()


def require_sha256(value: Any, label: str) -> str:
    if not isinstance(value, str) or len(value) != 64 or any(ch not in "0123456789abcdef" for ch in value):
        fail(f"{label} drift")
    return value


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

    authorization_keys = {key for key in frontier if key.endswith("_authorized")}
    if authorization_keys != set(AUTHORIZATION_FIELDS):
        fail("authorization rail set drift")
    if set(frontier) != TOP_LEVEL_FIELDS:
        fail("frontier field set drift")
    if frontier.get("format") != FORMAT or frontier.get("crs") != TARGET_CRS:
        fail("format/CRS drift")

    require_sha256(frontier.get("source_intersection_evidence_sha256"), "source intersection evidence sha")

    for field in AUTHORIZATION_FIELDS:
        if frontier.get(field) is not False:
            fail(f"authorization rail drift: {field}")

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
    if len(source_ids) != frontier["source_zero_intersection_road_count"]:
        fail("source road accounting drift")
    source_id_set = set(source_ids)

    uncovered_ids = require_int_list(
        frontier.get("uncovered_zero_intersection_road_osm_ids"),
        "uncovered road_osm_id",
        positive=True,
    )
    if uncovered_ids != sorted(set(uncovered_ids)):
        fail("uncovered road_osm_id order/uniqueness drift")
    if not set(uncovered_ids).issubset(source_id_set):
        fail("uncovered road outside source set")

    rows = frontier.get("candidate_cells")
    if not isinstance(rows, list):
        fail("candidate cells JSON type drift")
    if len(rows) != frontier["candidate_cell_count"]:
        fail("candidate cell accounting drift")

    seen_cell_ids: list[str] = []
    covered_id_set: set[int] = set()
    for row in rows:
        if not isinstance(row, dict):
            fail("candidate cell object drift")
        if set(row) != CANDIDATE_FIELDS:
            fail("candidate field set drift")
        if row.get("crs") != TARGET_CRS:
            fail("candidate cell CRS drift")
        require_int(row.get("cell_size_m"), "candidate cell_size_m")
        if row["cell_size_m"] != CELL_SIZE_M:
            fail("candidate cell_size_m value drift")

        bbox = require_int_list(row.get("bbox"), "candidate bbox")
        if len(bbox) != 4:
            fail("candidate bbox length drift")
        east, north, east_max, north_max = bbox
        if east_max != east + CELL_SIZE_M or north_max != north + CELL_SIZE_M:
            fail("candidate bbox grid drift")
        if east % CELL_SIZE_M != 0 or north % CELL_SIZE_M != 0:
            fail("candidate bbox grid alignment drift")
        expected_cell_id = f"bxl-e{east}-n{north}-s{CELL_SIZE_M}"
        if row.get("cell_id") != expected_cell_id:
            fail("candidate cell identity drift")
        seen_cell_ids.append(expected_cell_id)

        roads = require_int_list(row.get("road_osm_ids"), "candidate road_osm_id", positive=True)
        require_int(row.get("road_count"), "candidate road_count", minimum=0)
        if len(roads) != row["road_count"]:
            fail("candidate road accounting drift")
        if roads != sorted(set(roads)):
            fail("candidate road_osm_id order/uniqueness drift")
        road_set = set(roads)
        if not road_set.issubset(source_id_set):
            fail("candidate road outside source set")
        covered_id_set.update(road_set)

        if row.get("registered") is not False or row.get("source_registration_ready") is not False:
            fail("candidate readiness drift")
        if row.get("manifest_path") is not None:
            fail("candidate manifest readiness drift")
        unknown_row_auth = {key for key in row if key.endswith("_authorized")}
        if unknown_row_auth:
            fail("candidate authorization rail drift")

    if seen_cell_ids != sorted(set(seen_cell_ids)):
        fail("candidate cell order/uniqueness drift")

    uncovered_id_set = set(uncovered_ids)
    if covered_id_set & uncovered_id_set:
        fail("covered/uncovered road overlap drift")
    if covered_id_set | uncovered_id_set != source_id_set:
        fail("source road coverage accounting drift")
    if len(covered_id_set) != frontier["covered_zero_intersection_road_count"]:
        fail("covered road accounting drift")
    if len(uncovered_id_set) != frontier["uncovered_zero_intersection_road_count"]:
        fail("uncovered road accounting drift")
    if frontier["registered_cell_overlap_count"] != 0:
        fail("registered cell overlap accounting drift")

    stored = require_sha256(frontier.get("frontier_sha256"), "frontier sha")
    unsigned = dict(frontier)
    unsigned.pop("frontier_sha256", None)
    if stored != sha256_json(unsigned):
        fail("frontier sha drift")


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
