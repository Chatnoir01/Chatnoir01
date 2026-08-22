#!/usr/bin/env python3
"""Build fail-closed terrain/runtime readiness evidence for one Brussels cell.

This stage aggregates already-measured runtime gates. It never invents missing proof
and it never authorizes production. Even a fully green result only means that the
cell is ready for an explicit validated promotion step.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

FORMAT = "grand-bruxelles-terrain-runtime-readiness-v1"
TERRAIN_LOD_FORMAT = "grand-bruxelles-cell-dtm-lod-evidence-v1"
TERRAIN_CANDIDATE_FORMAT = "grand-bruxelles-cell-terrain-runtime-candidate-v1"
SECONDARY_FORMAT = "grand-bruxelles-citygen-secondary-height-validation-v1"
CANDIDATE_FORMAT = "grand-bruxelles-runtime-candidate-bundle-v1"
GATE_EVIDENCE_FORMAT = "grand-bruxelles-terrain-runtime-gate-evidence-v1"
CRS = "EPSG:31370"
RUNTIME_GATES = ("seams", "normals", "collisions", "streaming", "performance", "photo_match")


def _read(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def _digest(value: Any) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def _require_digest(name: str, value: Any) -> str:
    if not isinstance(value, str) or len(value) != 64 or any(c not in "0123456789abcdef" for c in value.lower()):
        raise ValueError(f"{name} must be a sha256 hex digest")
    return value.lower()


def _validate_base(terrain: dict[str, Any], terrain_candidate: dict[str, Any], secondary: dict[str, Any], candidate: dict[str, Any]) -> tuple[str, str, str, str, str]:
    if terrain.get("format") != TERRAIN_LOD_FORMAT or terrain.get("crs") != CRS:
        raise ValueError("unsupported terrain LOD evidence")
    if terrain_candidate.get("format") != TERRAIN_CANDIDATE_FORMAT or terrain_candidate.get("crs") != CRS:
        raise ValueError("unsupported terrain runtime candidate")
    if secondary.get("format") != SECONDARY_FORMAT or secondary.get("crs") != CRS:
        raise ValueError("unsupported secondary height validation")
    if candidate.get("format") != CANDIDATE_FORMAT:
        raise ValueError("unsupported runtime candidate evidence")

    cell_id = terrain.get("cell_id")
    if not isinstance(cell_id, str) or not cell_id.startswith("bxl-"):
        raise ValueError("terrain readiness cell identity missing")
    if terrain_candidate.get("cell_id") != cell_id or secondary.get("cell_id") != cell_id or candidate.get("cell_id") != cell_id:
        raise ValueError("terrain/runtime readiness identity mismatch")

    selection = terrain.get("selection")
    if not isinstance(selection, dict) or selection.get("selected_resolution_m") is None:
        raise ValueError("terrain LOD has no selected source-faithful candidate")
    if selection.get("canonical_edge_alignment_required") is not True:
        raise ValueError("terrain LOD does not lock canonical edge alignment")
    if terrain.get("runtime_approved") is not False:
        raise ValueError("terrain LOD evidence must remain runtime-unapproved")

    terrain_authorization = terrain_candidate.get("authorization")
    topology = terrain_candidate.get("topology")
    source = terrain_candidate.get("source")
    if not isinstance(terrain_authorization, dict) or not isinstance(topology, dict) or not isinstance(source, dict):
        raise ValueError("terrain runtime candidate safety/topology contract missing")
    if terrain_authorization.get("candidate_only") is not True:
        raise ValueError("terrain runtime candidate must remain candidate-only")
    for flag in ("terrain_runtime_authorized", "collision_authorized", "runtime_mount_authorized", "jouable_promotion_authorized"):
        if terrain_authorization.get(flag) is not False:
            raise ValueError(f"terrain runtime candidate unexpectedly authorizes {flag}")
    if topology.get("includes_all_four_canonical_cell_edges") is not True or topology.get("shared_edge_coordinates_are_exact") is not True:
        raise ValueError("terrain runtime candidate does not lock canonical shared edges")
    if abs(float(terrain_candidate.get("spacing_m", 0.0)) - float(selection["selected_resolution_m"])) > 1e-9:
        raise ValueError("terrain runtime candidate spacing drifted from selected LOD")

    if secondary.get("runtime_promotion_allowed") is not False:
        raise ValueError("secondary height validation unexpectedly authorizes runtime promotion")
    if secondary.get("secondary_validation_complete") is not True:
        raise ValueError("secondary height validation is incomplete")

    sealed = candidate.get("sealed")
    safety = candidate.get("safety")
    if not isinstance(sealed, dict) or not isinstance(safety, dict):
        raise ValueError("runtime candidate is not sealed with a safety contract")
    if sealed.get("production_discovery_eligible") is not False:
        raise ValueError("runtime candidate must remain production-ineligible")
    if sealed.get("requires_explicit_validated_promotion") is not True:
        raise ValueError("runtime candidate does not require explicit validated promotion")
    if safety.get("runtime_mount_authorized") is not False or safety.get("collision_generated") is not False:
        raise ValueError("runtime candidate safety contract drifted")

    terrain_digest = _require_digest("terrain evidence digest", terrain.get("evidence_digest"))
    terrain_candidate_digest = _require_digest("terrain runtime candidate digest", terrain_candidate.get("candidate_digest"))
    if source.get("terrain_lod_evidence_digest") != terrain_digest:
        raise ValueError("terrain runtime candidate is stale against terrain LOD evidence")
    secondary_digest = _require_digest("secondary validation digest", secondary.get("validation_digest"))
    candidate_digest = _require_digest("runtime candidate digest", candidate.get("candidate_digest"))
    return cell_id, terrain_digest, terrain_candidate_digest, secondary_digest, candidate_digest


def build(terrain_path: Path, terrain_candidate_path: Path, secondary_path: Path, candidate_path: Path, gate_evidence_path: Path | None = None) -> dict[str, Any]:
    terrain = _read(terrain_path)
    terrain_candidate = _read(terrain_candidate_path)
    secondary = _read(secondary_path)
    candidate = _read(candidate_path)
    cell_id, terrain_digest, terrain_candidate_digest, secondary_digest, candidate_digest = _validate_base(terrain, terrain_candidate, secondary, candidate)

    measured: dict[str, Any] = {}
    evidence_digest = None
    blockers: list[str] = []
    if gate_evidence_path is not None and gate_evidence_path.exists():
        gate_evidence = _read(gate_evidence_path)
        if gate_evidence.get("format") != GATE_EVIDENCE_FORMAT or gate_evidence.get("crs") != CRS:
            raise ValueError("unsupported terrain/runtime gate evidence")
        if gate_evidence.get("cell_id") != cell_id:
            raise ValueError("terrain/runtime gate evidence identity mismatch")
        bindings = gate_evidence.get("bindings")
        if not isinstance(bindings, dict):
            raise ValueError("terrain/runtime gate evidence bindings missing")
        if bindings.get("terrain_lod_evidence_digest") != terrain_digest:
            raise ValueError("terrain/runtime gate evidence is stale against terrain LOD evidence")
        if bindings.get("terrain_runtime_candidate_digest") != terrain_candidate_digest:
            raise ValueError("terrain/runtime gate evidence is stale against terrain runtime candidate")
        if bindings.get("secondary_height_validation_digest") != secondary_digest:
            raise ValueError("terrain/runtime gate evidence is stale against secondary height validation")
        if bindings.get("runtime_candidate_digest") != candidate_digest:
            raise ValueError("terrain/runtime gate evidence is stale against runtime candidate")
        gates = gate_evidence.get("gates")
        if not isinstance(gates, dict):
            raise ValueError("terrain/runtime gate evidence gates missing")
        measured = gates
        evidence_digest = _digest(gate_evidence)

    gate_rows: dict[str, Any] = {}
    passed_count = 0
    for gate in RUNTIME_GATES:
        row = measured.get(gate)
        if not isinstance(row, dict):
            gate_rows[gate] = {"passed": False, "status": "missing_evidence", "measurement_digest": None}
            blockers.append(f"runtime_gate_missing:{gate}")
            continue
        if row.get("cell_id") != cell_id:
            raise ValueError(f"runtime gate identity mismatch: {gate}")
        measurement_digest = _require_digest(f"{gate} measurement digest", row.get("measurement_digest"))
        passed = row.get("passed") is True
        status = str(row.get("status") or ("passed" if passed else "failed"))
        gate_rows[gate] = {"passed": passed, "status": status, "measurement_digest": measurement_digest}
        if passed:
            passed_count += 1
        else:
            blockers.append(f"runtime_gate_failed:{gate}")

    all_passed = passed_count == len(RUNTIME_GATES)
    result = {
        "format": FORMAT,
        "cell_id": cell_id,
        "crs": CRS,
        "bindings": {
            "terrain_lod_evidence_digest": terrain_digest,
            "terrain_runtime_candidate_digest": terrain_candidate_digest,
            "secondary_height_validation_digest": secondary_digest,
            "runtime_candidate_digest": candidate_digest,
            "runtime_gate_evidence_digest": evidence_digest,
        },
        "selected_terrain_resolution_m": terrain["selection"]["selected_resolution_m"],
        "runtime_gates": gate_rows,
        "runtime_gate_count": len(RUNTIME_GATES),
        "passed_runtime_gate_count": passed_count,
        "all_runtime_gates_passed": all_passed,
        "promotion_ready_for_explicit_review": all_passed,
        "runtime_promotion_allowed": False,
        "automatic_production_mutation": False,
        "blockers": sorted(set(blockers)),
        "next_action": "explicit_validated_promotion_required" if all_passed else "collect_measured_runtime_gate_evidence",
        "policy": {
            "per_cell_digest_binding_required": True,
            "measured_gates_bind_actual_terrain_artifact": True,
            "missing_evidence_never_assumed_passed": True,
            "global_workflow_green_is_not_cell_proof": True,
            "promotion_requires_separate_explicit_step": True,
        },
    }
    result["readiness_digest"] = _digest(result)
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--terrain-lod", type=Path, required=True)
    parser.add_argument("--terrain-runtime-candidate", type=Path, required=True)
    parser.add_argument("--secondary-height-validation", type=Path, required=True)
    parser.add_argument("--runtime-candidate", type=Path, required=True)
    parser.add_argument("--runtime-gate-evidence", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        result = build(args.terrain_lod, args.terrain_runtime_candidate, args.secondary_height_validation, args.runtime_candidate, args.runtime_gate_evidence)
    except Exception as exc:
        print(f"TERRAIN_RUNTIME_READINESS_ERROR: {exc}")
        return 1
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("TERRAIN_RUNTIME_READINESS_OK " f"cell={result['cell_id']} passed={result['passed_runtime_gate_count']}/{result['runtime_gate_count']} " f"promotion_ready={str(result['promotion_ready_for_explicit_review']).lower()} runtime_promotion=false")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
