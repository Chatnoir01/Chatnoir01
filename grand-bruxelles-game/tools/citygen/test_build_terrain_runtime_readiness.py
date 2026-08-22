#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("terrain_runtime_readiness", HERE / "build_terrain_runtime_readiness.py")
mod = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(mod)

CELL_ID = "bxl-e149000-n169000-s500"


def sha(ch: str) -> str:
    return ch * 64


def write(path: Path, payload: dict) -> None:
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    terrain_path = root / "terrain_lod_evidence.json"
    terrain_candidate_path = root / "terrain_runtime_candidate.json"
    secondary_path = root / "secondary_height_validation.json"
    candidate_path = root / "candidate.json"
    gates_path = root / "terrain_runtime_gate_evidence.json"

    terrain = {
        "format": mod.TERRAIN_LOD_FORMAT,
        "cell_id": CELL_ID,
        "crs": mod.CRS,
        "selection": {"selected_resolution_m": 2.0, "canonical_edge_alignment_required": True},
        "runtime_approved": False,
        "evidence_digest": sha("a"),
    }
    terrain_candidate = {
        "format": mod.TERRAIN_CANDIDATE_FORMAT,
        "cell_id": CELL_ID,
        "crs": mod.CRS,
        "spacing_m": 2.0,
        "topology": {"includes_all_four_canonical_cell_edges": True, "shared_edge_coordinates_are_exact": True},
        "source": {"terrain_lod_evidence_digest": terrain["evidence_digest"]},
        "authorization": {
            "candidate_only": True,
            "terrain_runtime_authorized": False,
            "collision_authorized": False,
            "runtime_mount_authorized": False,
            "jouable_promotion_authorized": False,
        },
        "candidate_digest": sha("d"),
    }
    secondary = {
        "format": mod.SECONDARY_FORMAT,
        "cell_id": CELL_ID,
        "crs": mod.CRS,
        "secondary_validation_complete": True,
        "runtime_promotion_allowed": False,
        "validation_digest": sha("b"),
    }
    candidate = {
        "format": mod.CANDIDATE_FORMAT,
        "cell_id": CELL_ID,
        "safety": {"runtime_mount_authorized": False, "collision_generated": False},
        "sealed": {"production_discovery_eligible": False, "requires_explicit_validated_promotion": True},
        "candidate_digest": sha("c"),
    }
    write(terrain_path, terrain)
    write(terrain_candidate_path, terrain_candidate)
    write(secondary_path, secondary)
    write(candidate_path, candidate)

    pending = mod.build(terrain_path, terrain_candidate_path, secondary_path, candidate_path)
    assert pending["passed_runtime_gate_count"] == 0
    assert pending["all_runtime_gates_passed"] is False
    assert pending["promotion_ready_for_explicit_review"] is False
    assert pending["runtime_promotion_allowed"] is False
    assert pending["automatic_production_mutation"] is False
    assert pending["next_action"] == "collect_measured_runtime_gate_evidence"
    assert len(pending["blockers"]) == len(mod.RUNTIME_GATES)
    assert pending["bindings"]["terrain_runtime_candidate_digest"] == terrain_candidate["candidate_digest"]

    gates = {
        "format": mod.GATE_EVIDENCE_FORMAT,
        "cell_id": CELL_ID,
        "crs": mod.CRS,
        "bindings": {
            "terrain_lod_evidence_digest": terrain["evidence_digest"],
            "terrain_runtime_candidate_digest": terrain_candidate["candidate_digest"],
            "secondary_height_validation_digest": secondary["validation_digest"],
            "runtime_candidate_digest": candidate["candidate_digest"],
        },
        "gates": {
            gate: {"cell_id": CELL_ID, "passed": True, "status": "passed", "measurement_digest": sha(str(index % 10))}
            for index, gate in enumerate(mod.RUNTIME_GATES, start=1)
        },
    }
    write(gates_path, gates)
    ready = mod.build(terrain_path, terrain_candidate_path, secondary_path, candidate_path, gates_path)
    assert ready["passed_runtime_gate_count"] == len(mod.RUNTIME_GATES)
    assert ready["all_runtime_gates_passed"] is True
    assert ready["promotion_ready_for_explicit_review"] is True
    assert ready["runtime_promotion_allowed"] is False
    assert ready["automatic_production_mutation"] is False
    assert ready["blockers"] == []
    assert ready["next_action"] == "explicit_validated_promotion_required"
    assert len(ready["readiness_digest"]) == 64

    failed = json.loads(json.dumps(gates))
    failed["gates"]["collisions"]["passed"] = False
    failed["gates"]["collisions"]["status"] = "failed_collision_shape_probe"
    write(gates_path, failed)
    blocked = mod.build(terrain_path, terrain_candidate_path, secondary_path, candidate_path, gates_path)
    assert blocked["promotion_ready_for_explicit_review"] is False
    assert "runtime_gate_failed:collisions" in blocked["blockers"]

    stale_runtime = json.loads(json.dumps(gates))
    stale_runtime["bindings"]["runtime_candidate_digest"] = sha("e")
    write(gates_path, stale_runtime)
    try:
        mod.build(terrain_path, terrain_candidate_path, secondary_path, candidate_path, gates_path)
    except ValueError as exc:
        assert "stale against runtime candidate" in str(exc)
    else:
        raise AssertionError("stale per-cell runtime gate evidence must fail closed")

    stale_terrain = json.loads(json.dumps(gates))
    stale_terrain["bindings"]["terrain_runtime_candidate_digest"] = sha("f")
    write(gates_path, stale_terrain)
    try:
        mod.build(terrain_path, terrain_candidate_path, secondary_path, candidate_path, gates_path)
    except ValueError as exc:
        assert "stale against terrain runtime candidate" in str(exc)
    else:
        raise AssertionError("stale measured terrain artifact evidence must fail closed")

    stale_secondary = json.loads(json.dumps(gates))
    stale_secondary["bindings"]["secondary_height_validation_digest"] = sha("9")
    write(gates_path, stale_secondary)
    try:
        mod.build(terrain_path, terrain_candidate_path, secondary_path, candidate_path, gates_path)
    except ValueError as exc:
        assert "stale against secondary height validation" in str(exc)
    else:
        raise AssertionError("stale secondary-height-bound runtime evidence must fail closed")

    incomplete_secondary = json.loads(json.dumps(secondary))
    incomplete_secondary["secondary_validation_complete"] = False
    write(secondary_path, incomplete_secondary)
    write(gates_path, gates)
    try:
        mod.build(terrain_path, terrain_candidate_path, secondary_path, candidate_path, gates_path)
    except ValueError as exc:
        assert "secondary height validation is incomplete" in str(exc)
    else:
        raise AssertionError("incomplete secondary height validation must fail closed")

print("TERRAIN_RUNTIME_READINESS_OK gates=6 lod_digest=true terrain_artifact_digest=true secondary_digest=true incomplete_secondary=false missing=false failed=false all_passed=review_only runtime_promotion=false")
