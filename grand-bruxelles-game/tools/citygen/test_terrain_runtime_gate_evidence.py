#!/usr/bin/env python3
from __future__ import annotations

import copy
import importlib.util
import json
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent


def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


candidate_mod = load("terrain_candidate", HERE / "build_cell_terrain_runtime_candidate.py")
geometry_mod = load("terrain_geometry_gates", HERE / "measure_terrain_geometry_gates.py")
evidence_mod = load("terrain_gate_evidence", HERE / "build_terrain_runtime_gate_evidence.py")
readiness_mod = load("terrain_readiness", HERE / "build_terrain_runtime_readiness.py")

try:
    import numpy as np
except ImportError as exc:
    raise SystemExit(f"numpy missing in runner: {exc}")

CENTER = "bxl-e149000-n169000-s500"
EAST = "bxl-e149010-n169000-s500"
CENTER_BBOX = (149000.0, 169000.0, 149010.0, 169010.0)
EAST_BBOX = (149010.0, 169000.0, 149020.0, 169010.0)
SPACING = 2.0


def write(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def make_terrain_candidate(cell_id: str, bbox: tuple[float, float, float, float], grid: np.ndarray, lod_digest: str = "a" * 64) -> dict:
    encoding, decoded = candidate_mod._encode_heightfield(np.asarray(grid, dtype=np.float64))
    result = {
        "format": candidate_mod.FORMAT,
        "cell_id": cell_id,
        "crs": candidate_mod.CRS,
        "bbox_epsg31370": [float(v) for v in bbox],
        "spacing_m": SPACING,
        "shape": [int(grid.shape[0]), int(grid.shape[1])],
        "sample_count": int(grid.size),
        "topology": {
            "includes_all_four_canonical_cell_edges": True,
            "columns_increase_easting": True,
            "rows_increase_northing": True,
            "godot_world_z_decreases_with_northing": True,
            "shared_edge_coordinates_are_exact": True,
        },
        "source": {
            "kind": "official_validated_DTM",
            "terrain_lod_evidence_digest": lod_digest,
            "raster_validation_digest": "9" * 64,
            "selected_level_p95_abs_error_m": 0.08,
            "selected_level_vertex_error_evaluated": True,
        },
        "height_encoding": encoding,
        "decoded_height_min_m": round(float(decoded.min()), 6),
        "decoded_height_max_m": round(float(decoded.max()), 6),
        "authorization": {
            "candidate_only": True,
            "terrain_runtime_authorized": False,
            "collision_authorized": False,
            "runtime_mount_authorized": False,
            "jouable_promotion_authorized": False,
        },
        "status": "qa_terrain_runtime_candidate_pending_measured_gates",
    }
    digest_view = copy.deepcopy(result)
    digest_view["height_encoding"].pop("payload_base64", None)
    result["candidate_digest"] = candidate_mod._digest(digest_view)
    return result


def base_artifacts(center_candidate: dict) -> tuple[dict, dict, dict]:
    terrain = {
        "format": readiness_mod.TERRAIN_LOD_FORMAT,
        "cell_id": CENTER,
        "crs": readiness_mod.CRS,
        "selection": {"selected_resolution_m": SPACING, "canonical_edge_alignment_required": True},
        "runtime_approved": False,
        "evidence_digest": "a" * 64,
    }
    secondary = {
        "format": readiness_mod.SECONDARY_FORMAT,
        "cell_id": CENTER,
        "crs": readiness_mod.CRS,
        "secondary_validation_complete": True,
        "runtime_promotion_allowed": False,
        "validation_digest": "b" * 64,
    }
    runtime = {
        "format": readiness_mod.CANDIDATE_FORMAT,
        "cell_id": CENTER,
        "safety": {"runtime_mount_authorized": False, "collision_generated": False},
        "sealed": {"production_discovery_eligible": False, "requires_explicit_validated_promotion": True},
        "candidate_digest": "c" * 64,
    }
    assert center_candidate["source"]["terrain_lod_evidence_digest"] == terrain["evidence_digest"]
    return terrain, secondary, runtime


def make_single_gate_bundle(bindings: dict, gate: str = "streaming", passed: bool = True) -> dict:
    row = {
        "cell_id": CENTER,
        "gate": gate,
        "passed": passed,
        "status": "passed_fixture" if passed else "failed_fixture",
        "source": "deterministic_test_fixture",
        "metrics": {"fixture": True},
    }
    row["measurement_digest"] = geometry_mod._digest(row)
    bundle = {
        "format": evidence_mod.MEASUREMENT_FORMAT,
        "cell_id": CENTER,
        "crs": readiness_mod.CRS,
        "bindings": copy.deepcopy(bindings),
        "gates": {gate: row},
        "policy": {"runtime_promotion_allowed": False},
    }
    bundle["measurement_bundle_digest"] = geometry_mod._digest(bundle)
    return bundle


with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    sources = root / "sources"
    rows, cols = np.mgrid[0:6, 0:6]
    center_grid = 50.0 + 0.20 * cols + 0.10 * rows
    east_grid = 51.0 + 0.20 * cols + 0.10 * rows
    center_candidate = make_terrain_candidate(CENTER, CENTER_BBOX, center_grid)
    east_candidate = make_terrain_candidate(EAST, EAST_BBOX, east_grid)
    terrain, secondary, runtime = base_artifacts(center_candidate)

    terrain_path = root / "terrain_lod_evidence.json"
    center_path = sources / CENTER / "terrain_runtime_candidate.json"
    secondary_path = root / "secondary_height_validation.json"
    runtime_path = root / "candidate.json"
    target_path = root / "brussels_regional_target_grid.json"
    measurement_path = root / "geometry_measurement.json"
    evidence_path = root / "terrain_runtime_gate_evidence.json"
    persisted_streaming_path = root / "terrain_streaming_gate_measurement.json"
    east_path = sources / EAST / "terrain_runtime_candidate.json"

    write(terrain_path, terrain)
    write(center_path, center_candidate)
    write(east_path, east_candidate)
    write(secondary_path, secondary)
    write(runtime_path, runtime)
    write(target_path, {
        "format": geometry_mod.TARGET_FORMAT,
        "crs": geometry_mod.CRS,
        "cell_size_m": 10.0,
        "cells": [
            {"cell_id": CENTER, "bbox": list(CENTER_BBOX), "municipalities": ["test"]},
            {"cell_id": EAST, "bbox": list(EAST_BBOX), "municipalities": ["test"]},
        ],
    })

    measured = geometry_mod.measure(terrain_path, center_path, secondary_path, runtime_path, target_path, sources)
    assert measured["gates"]["seams"]["passed"] is True, measured["gates"]["seams"]
    assert measured["gates"]["seams"]["metrics"]["expected_neighbor_count"] == 1
    assert measured["gates"]["seams"]["metrics"]["max_observed_abs_delta_m"] == 0.0
    assert measured["gates"]["normals"]["passed"] is True, measured["gates"]["normals"]
    assert measured["policy"]["unmeasured_gates_are_not_inferred"] is True
    assert measured["policy"]["neighbor_candidate_bbox_must_match_target_grid"] is True
    write(measurement_path, measured)

    evidence = evidence_mod.build(terrain_path, center_path, secondary_path, runtime_path, [measurement_path])
    assert evidence["measured_gate_count"] == 2
    assert set(evidence["gates"]) == {"seams", "normals"}
    assert evidence["missing_runtime_gates"] == ["collisions", "streaming", "performance", "photo_match"]
    assert evidence["policy"]["runtime_promotion_allowed"] is False
    write(evidence_path, evidence)

    readiness = readiness_mod.build(terrain_path, center_path, secondary_path, runtime_path, evidence_path)
    assert readiness["passed_runtime_gate_count"] == 2, readiness
    assert readiness["promotion_ready_for_explicit_review"] is False
    assert readiness["runtime_promotion_allowed"] is False
    assert {"runtime_gate_missing:collisions", "runtime_gate_missing:streaming", "runtime_gate_missing:performance", "runtime_gate_missing:photo_match"}.issubset(set(readiness["blockers"]))

    streaming_bundle = make_single_gate_bundle(measured["bindings"], "streaming", True)
    write(persisted_streaming_path, streaming_bundle)
    preserved = evidence_mod.build(terrain_path, center_path, secondary_path, runtime_path, [measurement_path])
    assert preserved["measured_gate_count"] == 3
    assert set(preserved["gates"]) == {"seams", "normals", "streaming"}
    assert preserved["gates"]["streaming"]["passed"] is True
    assert preserved["missing_runtime_gates"] == ["collisions", "performance", "photo_match"]
    assert preserved["policy"]["persisted_measurement_files_checked"] == ["terrain_streaming_gate_measurement.json"]
    assert preserved["policy"]["stale_persisted_measurements_skipped"] == []

    reused = evidence_mod.build(
        terrain_path, center_path, secondary_path, runtime_path, [persisted_streaming_path],
        existing_evidence_path=evidence_path,
        discover_persisted_measurements=False,
    )
    assert reused["measured_gate_count"] == 3
    assert set(reused["gates"]) == {"seams", "normals", "streaming"}
    assert reused["policy"]["existing_gate_evidence_reused"] is True

    stale_persisted = copy.deepcopy(streaming_bundle)
    stale_persisted["bindings"]["runtime_candidate_digest"] = "d" * 64
    stale_persisted.pop("measurement_bundle_digest", None)
    stale_persisted["measurement_bundle_digest"] = geometry_mod._digest(stale_persisted)
    write(persisted_streaming_path, stale_persisted)
    stale_skipped = evidence_mod.build(terrain_path, center_path, secondary_path, runtime_path, [measurement_path])
    assert stale_skipped["measured_gate_count"] == 2
    assert set(stale_skipped["gates"]) == {"seams", "normals"}
    assert stale_skipped["policy"]["stale_persisted_measurements_skipped"] == ["terrain_streaming_gate_measurement.json"]

    corrupted_persisted = copy.deepcopy(streaming_bundle)
    corrupted_persisted["gates"]["streaming"]["status"] = "tampered_without_gate_rehash"
    corrupted_persisted.pop("measurement_bundle_digest", None)
    corrupted_persisted["measurement_bundle_digest"] = geometry_mod._digest(corrupted_persisted)
    write(persisted_streaming_path, corrupted_persisted)
    try:
        evidence_mod.build(terrain_path, center_path, secondary_path, runtime_path, [measurement_path])
    except ValueError as exc:
        assert "measurement digest mismatch: streaming" in str(exc)
    else:
        raise AssertionError("corrupted persisted streaming measurement must fail closed")
    write(persisted_streaming_path, streaming_bundle)

    east_path.unlink()
    pending = geometry_mod.measure(terrain_path, center_path, secondary_path, runtime_path, target_path, sources)
    assert pending["gates"]["seams"]["passed"] is False
    assert pending["gates"]["seams"]["status"] == "pending_neighbor_candidates"
    assert pending["gates"]["seams"]["metrics"]["missing_neighbor_cell_ids"] == [EAST]
    assert pending["gates"]["normals"]["passed"] is True

    wrong_bbox = (149010.0, 169010.0, 149020.0, 169020.0)
    write(east_path, make_terrain_candidate(EAST, wrong_bbox, east_grid))
    wrong_neighbor = geometry_mod.measure(terrain_path, center_path, secondary_path, runtime_path, target_path, sources)
    assert wrong_neighbor["gates"]["seams"]["passed"] is False
    assert wrong_neighbor["gates"]["seams"]["status"] == "failed_invalid_neighbor_candidate"
    invalid = wrong_neighbor["gates"]["seams"]["metrics"]["invalid_neighbors"]
    assert len(invalid) == 1 and "bbox does not match regional target grid" in invalid[0]["error"]
    write(east_path, east_candidate)

    stale = copy.deepcopy(measured)
    stale["bindings"]["runtime_candidate_digest"] = "d" * 64
    stale.pop("measurement_bundle_digest", None)
    stale["measurement_bundle_digest"] = geometry_mod._digest(stale)
    stale_path = root / "stale.json"
    write(stale_path, stale)
    try:
        evidence_mod.build(terrain_path, center_path, secondary_path, runtime_path, [stale_path])
    except ValueError as exc:
        assert "stale against exact cell artifacts" in str(exc)
    else:
        raise AssertionError("stale explicit measurement binding must fail closed")

    tampered = copy.deepcopy(measured)
    tampered["gates"]["normals"]["status"] = "tampered_without_rehash"
    tampered.pop("measurement_bundle_digest", None)
    tampered["measurement_bundle_digest"] = geometry_mod._digest(tampered)
    tampered_path = root / "tampered.json"
    write(tampered_path, tampered)
    try:
        evidence_mod.build(terrain_path, center_path, secondary_path, runtime_path, [tampered_path])
    except ValueError as exc:
        assert "measurement digest mismatch: normals" in str(exc)
    else:
        raise AssertionError("tampered gate row must fail closed")

    conflict = copy.deepcopy(measured)
    conflict_row = conflict["gates"]["seams"]
    conflict_row["passed"] = False
    conflict_row["status"] = "synthetic_conflict"
    conflict_row.pop("measurement_digest", None)
    conflict_row["measurement_digest"] = geometry_mod._digest(conflict_row)
    conflict.pop("measurement_bundle_digest", None)
    conflict["measurement_bundle_digest"] = geometry_mod._digest(conflict)
    conflict_path = root / "conflict.json"
    write(conflict_path, conflict)
    try:
        evidence_mod.build(terrain_path, center_path, secondary_path, runtime_path, [measurement_path, conflict_path])
    except ValueError as exc:
        assert "conflicting measured runtime gate evidence: seams" in str(exc)
    else:
        raise AssertionError("conflicting duplicate gate measurements must fail closed")

    steep_grid = 50.0 + 120.0 * cols + 0.10 * rows
    steep_candidate = make_terrain_candidate(CENTER, CENTER_BBOX, steep_grid)
    write(center_path, steep_candidate)
    steep_terrain = copy.deepcopy(terrain)
    steep_terrain["evidence_digest"] = steep_candidate["source"]["terrain_lod_evidence_digest"]
    write(terrain_path, steep_terrain)
    steep = geometry_mod.measure(terrain_path, center_path, secondary_path, runtime_path, target_path, sources)
    assert steep["gates"]["normals"]["passed"] is False
    assert steep["gates"]["normals"]["status"] == "failed_degenerate_or_nonfinite_normals"

print(
    "TERRAIN_RUNTIME_GATE_EVIDENCE_GUARDRAILS_OK seams=measured normals=measured "
    "persisted_streaming=preserved stale_persisted=skipped corrupted_persisted=rejected "
    "missing_neighbor=pending wrong_neighbor_bbox=rejected stale_binding=rejected tamper=rejected "
    "conflict=rejected remaining_gates=missing runtime_promotion=false"
)
