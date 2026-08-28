#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / "tools/build_discovered_road_cell_coverage_frontier.py"
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


def rehash(tool, payload: dict) -> None:
    payload["frontier_sha256"] = tool.sha256_json({k: v for k, v in payload.items() if k != "frontier_sha256"})


def main() -> int:
    tool = load(TOOL, "discovered_road_cell_coverage_frontier")
    frontier = tool.build_frontier(SOURCE, FRAME, CELLS)
    tool.validate_frontier(frontier, SOURCE, FRAME, CELLS)

    assert frontier["source_zero_intersection_road_count"] == 41
    assert frontier["candidate_cell_count"] >= 1
    assert frontier["covered_zero_intersection_road_count"] == 41
    assert frontier["uncovered_zero_intersection_road_count"] == 0
    assert frontier["registered_cell_overlap_count"] == 0
    assert frontier["cell_registration_authorized"] is False
    assert frontier["road_cell_mapping_authorized"] is False
    assert frontier["runtime_mount_authorized"] is False
    assert frontier["jouable_authorized"] is False

    road_ids = frontier["source_zero_intersection_road_osm_ids"]
    assert road_ids == sorted(set(road_ids))
    covered = sorted({rid for row in frontier["candidate_cells"] for rid in row["road_osm_ids"]})
    assert covered == road_ids

    tampered = json.loads(json.dumps(frontier))
    tampered["candidate_cells"][0]["cell_id"] += "-tampered"
    rehash(tool, tampered)
    expect_fail(lambda: tool.validate_frontier(tampered, SOURCE, FRAME, CELLS), "candidate cell bbox identity drift")

    opened = json.loads(json.dumps(frontier))
    opened["cell_registration_authorized"] = True
    rehash(tool, opened)
    expect_fail(lambda: tool.validate_structure(opened), "authorization opened")

    injected = json.loads(json.dumps(frontier))
    foreign_road_id = max(road_ids) + 1
    assert foreign_road_id not in road_ids
    injected["candidate_cells"][0]["road_osm_ids"].append(foreign_road_id)
    injected["candidate_cells"][0]["road_osm_ids"].sort()
    injected["candidate_cells"][0]["road_count"] += 1
    injected["covered_zero_intersection_road_count"] += 1
    rehash(tool, injected)
    expect_fail(lambda: tool.validate_structure(injected), "candidate road outside zero-intersection set")

    cells_doc = json.loads(CELLS.read_text(encoding="utf-8"))
    entries = cells_doc.get("entries")
    assert isinstance(entries, list) and entries
    cells_doc["entries"].append(json.loads(json.dumps(entries[0])))
    with tempfile.TemporaryDirectory() as td:
        duplicate_cells = Path(td) / "registered-cells-duplicate.json"
        duplicate_cells.write_text(json.dumps(cells_doc), encoding="utf-8")
        expect_fail(lambda: tool.build_frontier(SOURCE, FRAME, duplicate_cells), "duplicate registered cell")

    opened_registry = json.loads(CELLS.read_text(encoding="utf-8"))
    opened_registry["runtime_mount_authorized"] = True
    with tempfile.TemporaryDirectory() as td:
        opened_cells = Path(td) / "registered-cells-opened.json"
        opened_cells.write_text(json.dumps(opened_registry), encoding="utf-8")
        expect_fail(lambda: tool.load_registered_cell_ids(opened_cells), "registered cell authorization opened")

    opened_entry = json.loads(CELLS.read_text(encoding="utf-8"))
    opened_entry["entries"][0]["safe_spawn_authorized"] = True
    with tempfile.TemporaryDirectory() as td:
        opened_entry_cells = Path(td) / "registered-cell-entry-opened.json"
        opened_entry_cells.write_text(json.dumps(opened_entry), encoding="utf-8")
        expect_fail(lambda: tool.load_registered_cell_ids(opened_entry_cells), "registered cell entry authorization opened")

    tampered_manifest_hash = json.loads(CELLS.read_text(encoding="utf-8"))
    tampered_manifest_hash["entries"][0]["manifest_sha256"] = "0" * 64
    with tempfile.TemporaryDirectory() as td:
        bad_manifest_registry = Path(td) / "registered-cell-manifest-hash-drift.json"
        bad_manifest_registry.write_text(json.dumps(tampered_manifest_hash), encoding="utf-8")
        expect_fail(lambda: tool.load_registered_cell_ids(bad_manifest_registry), "registered cell manifest sha drift")

    manifest_row = json.loads(CELLS.read_text(encoding="utf-8"))["entries"][0]
    manifest_doc = json.loads((ROOT / manifest_row["manifest_path"]).read_text(encoding="utf-8"))
    manifest_identity_drift = json.loads(json.dumps(manifest_doc))
    manifest_identity_drift["cell_id"] += "-tampered"
    expect_fail(
        lambda: tool.validate_registered_cell_manifest_identity(manifest_identity_drift, manifest_row),
        "registered cell manifest identity drift",
    )

    manifest_bbox_drift = json.loads(json.dumps(manifest_doc))
    manifest_bbox_drift["bbox"][0] += 500.0
    expect_fail(
        lambda: tool.validate_registered_cell_manifest_identity(manifest_bbox_drift, manifest_row),
        "registered cell manifest identity drift",
    )

    manifest_maturity_drift = json.loads(json.dumps(manifest_doc))
    manifest_maturity_drift["maturity"]["state"] = "runtime_ready"
    expect_fail(
        lambda: tool.validate_registered_cell_manifest_identity(manifest_maturity_drift, manifest_row),
        "registered cell manifest maturity drift",
    )

    manifest_gate_opened = json.loads(json.dumps(manifest_doc))
    manifest_gate_opened["maturity"]["gates"]["runtime_geometry"] = True
    expect_fail(
        lambda: tool.validate_registered_cell_manifest_identity(manifest_gate_opened, manifest_row),
        "registered cell manifest gate opened",
    )

    manifest_gate_omitted = json.loads(json.dumps(manifest_doc))
    del manifest_gate_omitted["maturity"]["gates"]["runtime_geometry"]
    expect_fail(
        lambda: tool.validate_registered_cell_manifest_identity(manifest_gate_omitted, manifest_row),
        "registered cell manifest gate set drift",
    )

    print("DISCOVERED_ROAD_CELL_COVERAGE_FRONTIER_TEST_GREEN")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
