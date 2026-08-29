#!/usr/bin/env python3
from __future__ import annotations

import hashlib
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


def rehash(frontier: dict) -> None:
    unsigned = dict(frontier)
    unsigned.pop("frontier_sha256", None)
    canonical = json.dumps(unsigned, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    frontier["frontier_sha256"] = hashlib.sha256(canonical.encode("utf-8")).hexdigest()


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

    authorization_string = json.loads(json.dumps(frontier))
    authorization_string["runtime_mount_authorized"] = "false"
    rehash(authorization_string)
    expect_fail(lambda: strict_validate(authorization_string), "authorization rail drift")

    unknown_authorization = json.loads(json.dumps(frontier))
    unknown_authorization["experimental_runtime_authorized"] = False
    rehash(unknown_authorization)
    expect_fail(lambda: strict_validate(unknown_authorization), "authorization rail set drift")

    unknown_top_level = json.loads(json.dumps(frontier))
    unknown_top_level["safe_spawn_ready"] = True
    rehash(unknown_top_level)
    expect_fail(lambda: strict_validate(unknown_top_level), "frontier field set drift")

    unknown_candidate_field = json.loads(json.dumps(frontier))
    unknown_candidate_field["candidate_cells"][0]["rendered"] = True
    rehash(unknown_candidate_field)
    expect_fail(lambda: strict_validate(unknown_candidate_field), "candidate field set drift")

    cell_identity = json.loads(json.dumps(frontier))
    cell_identity["candidate_cells"][0]["cell_id"] = "bxl-e000000-n000000-s500"
    rehash(cell_identity)
    expect_fail(lambda: strict_validate(cell_identity), "candidate cell identity drift")

    grid_alignment = json.loads(json.dumps(frontier))
    grid_row = grid_alignment["candidate_cells"][0]
    grid_row["bbox"] = [value + 1 for value in grid_row["bbox"]]
    east, north = grid_row["bbox"][0], grid_row["bbox"][1]
    grid_row["cell_id"] = f"bxl-e{east}-n{north}-s500"
    rehash(grid_alignment)
    expect_fail(lambda: strict_validate(grid_alignment), "candidate bbox grid alignment drift")

    candidate_manifest = json.loads(json.dumps(frontier))
    candidate_manifest["candidate_cells"][0]["manifest_path"] = "data/cell_manifests/unreviewed.json"
    rehash(candidate_manifest)
    expect_fail(lambda: strict_validate(candidate_manifest), "candidate manifest readiness drift")

    candidate_membership = json.loads(json.dumps(frontier))
    source_ids = set(candidate_membership["source_zero_intersection_road_osm_ids"])
    replacement = max(source_ids) + 1000000
    row = candidate_membership["candidate_cells"][0]
    row["road_osm_ids"][0] = replacement
    row["road_osm_ids"] = sorted(row["road_osm_ids"])
    rehash(candidate_membership)
    expect_fail(lambda: strict_validate(candidate_membership), "candidate road outside source set")

    digest_drift = json.loads(json.dumps(frontier))
    digest_drift["frontier_sha256"] = "0" * 64
    expect_fail(lambda: strict_validate(digest_drift), "frontier sha drift")

    print("DISCOVERED_ROAD_CELL_FRONTIER_JSON_TYPES_TEST_GREEN")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
