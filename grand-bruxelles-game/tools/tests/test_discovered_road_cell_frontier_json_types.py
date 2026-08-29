#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BUILDER = ROOT / "tools/build_discovered_road_cell_coverage_frontier.py"
STRICT_VALIDATOR = ROOT / "tools/validate_discovered_road_cell_frontier_json_types.py"
SOURCE = ROOT / "data/osm/vertical_slice_01.game.json"
FRAME = ROOT / "data/qa/osm_road_frame_correction_impact.contract.json"
CELLS = ROOT / "data/provenance/brussels_registered_cell_manifest_index.json"


def load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def expect_fail(fn, needle: str) -> None:
    try:
        fn()
    except SystemExit as exc:
        assert needle in str(exc), str(exc)
    else:
        raise AssertionError(f"expected failure containing {needle!r}")


def strict_validate(frontier: dict) -> None:
    if STRICT_VALIDATOR.is_file():
        strict = load(STRICT_VALIDATOR, "road_cell_frontier_json_types")
        strict.validate_frontier_json_types(frontier)
        return
    builder = load(BUILDER, "road_cell_frontier_builder_fallback")
    builder.validate_structure(frontier)


def main() -> int:
    builder = load(BUILDER, "road_cell_frontier_builder")
    frontier = builder.build_frontier(SOURCE, FRAME, CELLS)
    strict_validate(frontier)

    global_size_string = json.loads(json.dumps(frontier))
    global_size_string["cell_size_m"] = str(global_size_string["cell_size_m"])
    expect_fail(lambda: strict_validate(global_size_string), "cell_size_m JSON type drift")

    row_size_string = json.loads(json.dumps(frontier))
    row_size_string["candidate_cells"][0]["cell_size_m"] = str(row_size_string["candidate_cells"][0]["cell_size_m"])
    expect_fail(lambda: strict_validate(row_size_string), "candidate cell_size_m JSON type drift")

    bbox_float = json.loads(json.dumps(frontier))
    bbox_float["candidate_cells"][0]["bbox"][0] = float(bbox_float["candidate_cells"][0]["bbox"][0])
    expect_fail(lambda: strict_validate(bbox_float), "candidate bbox JSON type drift")

    road_id_string = json.loads(json.dumps(frontier))
    road_id_string["source_zero_intersection_road_osm_ids"][0] = str(road_id_string["source_zero_intersection_road_osm_ids"][0])
    expect_fail(lambda: strict_validate(road_id_string), "source road_osm_id JSON type drift")

    candidate_road_id_string = json.loads(json.dumps(frontier))
    candidate_road_id_string["candidate_cells"][0]["road_osm_ids"][0] = str(candidate_road_id_string["candidate_cells"][0]["road_osm_ids"][0])
    expect_fail(lambda: strict_validate(candidate_road_id_string), "candidate road_osm_id JSON type drift")

    print("DISCOVERED_ROAD_CELL_FRONTIER_JSON_TYPES_TEST_GREEN")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
