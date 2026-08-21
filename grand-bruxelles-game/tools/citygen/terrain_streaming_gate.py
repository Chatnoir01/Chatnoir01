#!/usr/bin/env python3
"""Prepare/finalize an exact per-cell Godot streaming measurement bundle.

The probe is QA-only. It loads a *sealed runtime candidate* through the same generic
Brussels source-plan renderer and the existing streaming manager/backend, but it never
adds the candidate to the production runtime index and never authorizes production.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent


def _load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot import {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


readiness_mod = _load("terrain_streaming_readiness", HERE / "build_terrain_runtime_readiness.py")
gate_mod = _load("terrain_streaming_gate_evidence", HERE / "build_terrain_runtime_gate_evidence.py")

PROBE_FORMAT = "grand-bruxelles-terrain-streaming-godot-probe-v1"
RESULT_FORMAT = "grand-bruxelles-terrain-streaming-godot-result-v1"
MEASUREMENT_FORMAT = gate_mod.MEASUREMENT_FORMAT
CRS = readiness_mod.CRS
ENGINE_VERSION = "4.7.1"
CANDIDATE_ROOT_FORMAT = "grand-bruxelles-urbis-built-cell-candidate-v1"
RUNTIME_CELL_FORMAT = "grand-bruxelles-urbis-cell-runtime-v1"
RUNTIME_NETWORK_FORMAT = "grand-bruxelles-urbis-network-cell-runtime-v2"


def _read(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def _digest(value: Any) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def _file_sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _require_sha(name: str, value: Any) -> str:
    if not isinstance(value, str) or len(value) != 64 or any(ch not in "0123456789abcdef" for ch in value.lower()):
        raise ValueError(f"{name} must be sha256 hex")
    return value.lower()


def _validate_bundle_files(candidate_dir: Path, cell_id: str, candidate: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any]]:
    manifest_path = candidate_dir / "manifest.json"
    runtime_cell_path = candidate_dir / "runtime" / "cell.game.json"
    runtime_network_path = candidate_dir / "runtime" / "network.game.json"
    for path in (manifest_path, runtime_cell_path, runtime_network_path):
        if not path.is_file():
            raise ValueError(f"sealed runtime candidate payload missing: {path.relative_to(candidate_dir)}")

    expected_hashes = candidate.get("output_sha256")
    if not isinstance(expected_hashes, dict):
        raise ValueError("sealed runtime candidate output hashes missing")
    actual_hashes = {
        "manifest.json": _file_sha(manifest_path),
        "runtime/cell.game.json": _file_sha(runtime_cell_path),
        "runtime/network.game.json": _file_sha(runtime_network_path),
    }
    if expected_hashes != actual_hashes:
        raise ValueError("sealed runtime candidate payload hash drift")

    manifest = _read(manifest_path)
    runtime_cell = _read(runtime_cell_path)
    runtime_network = _read(runtime_network_path)
    if manifest.get("format") != CANDIDATE_ROOT_FORMAT or manifest.get("crs") != CRS:
        raise ValueError("streaming probe requires a sealed candidate root manifest")
    if manifest.get("cell_id") != cell_id or runtime_cell.get("cell_id") != cell_id or runtime_network.get("cell_id") != cell_id:
        raise ValueError("streaming candidate identity mismatch")
    if runtime_cell.get("format") != RUNTIME_CELL_FORMAT or runtime_network.get("format") != RUNTIME_NETWORK_FORMAT:
        raise ValueError("streaming candidate runtime schema mismatch")
    promotion = manifest.get("promotion")
    authorization = manifest.get("authorization")
    if not isinstance(promotion, dict) or promotion.get("production_discovery_eligible") is not False:
        raise ValueError("streaming QA candidate unexpectedly production-discoverable")
    if not isinstance(authorization, dict) or authorization.get("candidate_only") is not True:
        raise ValueError("streaming QA manifest is not candidate-only")
    if authorization.get("runtime_mount_authorized") is not False or authorization.get("collision_authorized") is not False:
        raise ValueError("streaming QA candidate unexpectedly authorizes runtime/collision")
    return manifest, runtime_cell, runtime_network


def _world_center(manifest: dict[str, Any], runtime_cell: dict[str, Any]) -> list[float]:
    bbox = manifest.get("bbox")
    coords = runtime_cell.get("coordinate_system")
    if not isinstance(bbox, list) or len(bbox) != 4 or not isinstance(coords, dict):
        raise ValueError("candidate world-center contract missing")
    if coords.get("coordinates_are_current_game_world") is not True:
        raise ValueError("candidate coordinates are not locked to current game world")
    center_e = (float(bbox[0]) + float(bbox[2])) * 0.5
    center_n = (float(bbox[1]) + float(bbox[3])) * 0.5
    x = float(coords.get("world_anchor_x")) + center_e - float(coords.get("lambert_origin_e"))
    z = float(coords.get("world_anchor_z")) - (center_n - float(coords.get("lambert_origin_n")))
    return [round(x, 6), 0.0, round(z, 6)]


def _resource_path(root: str, suffix: str) -> str:
    base = root.rstrip("/")
    if not base.startswith("res://"):
        raise ValueError("Godot candidate resource root must be res://")
    return f"{base}/{suffix}"


def prepare(
    terrain_path: Path,
    terrain_candidate_path: Path,
    secondary_path: Path,
    runtime_candidate_path: Path,
    candidate_dir: Path,
    candidate_resource_root: str,
) -> dict[str, Any]:
    terrain = _read(terrain_path)
    terrain_candidate = _read(terrain_candidate_path)
    secondary = _read(secondary_path)
    candidate = _read(runtime_candidate_path)
    cell_id, terrain_digest, terrain_candidate_digest, secondary_digest, runtime_digest = readiness_mod._validate_base(
        terrain, terrain_candidate, secondary, candidate
    )
    if candidate_dir.name != cell_id:
        raise ValueError("runtime candidate directory identity mismatch")
    if candidate.get("candidate_digest") != runtime_digest:
        raise ValueError("runtime candidate digest changed after readiness validation")
    manifest, runtime_cell, runtime_network = _validate_bundle_files(candidate_dir, cell_id, candidate)

    runtime_contract = manifest.get("runtime")
    if not isinstance(runtime_contract, dict):
        raise ValueError("candidate runtime manifest contract missing")
    expected_buildings = int((runtime_contract.get("geometry_stats") or {}).get("buildings", -1))
    expected_surfaces = int((runtime_contract.get("geometry_stats") or {}).get("street_surfaces", -1))
    expected_streets = int((runtime_contract.get("network_stats") or {}).get("street_segments", -1))
    if min(expected_buildings, expected_surfaces, expected_streets) < 0:
        raise ValueError("candidate runtime stats missing")

    probe = {
        "format": PROBE_FORMAT,
        "cell_id": cell_id,
        "crs": CRS,
        "engine_version": ENGINE_VERSION,
        "bindings": {
            "terrain_lod_evidence_digest": terrain_digest,
            "terrain_runtime_candidate_digest": terrain_candidate_digest,
            "secondary_height_validation_digest": secondary_digest,
            "runtime_candidate_digest": runtime_digest,
        },
        "candidate_files": {
            "manifest": _resource_path(candidate_resource_root, "manifest.json"),
            "runtime_cell": _resource_path(candidate_resource_root, "runtime/cell.game.json"),
            "runtime_network": _resource_path(candidate_resource_root, "runtime/network.game.json"),
        },
        "candidate_output_sha256": copy.deepcopy(candidate["output_sha256"]),
        "world_center": _world_center(manifest, runtime_cell),
        "expected": {
            "buildings": expected_buildings,
            "street_surfaces": expected_surfaces,
            "street_segments": expected_streets,
        },
        "streaming_config": {
            "visual_load_radius_m": 300.0,
            "visual_unload_radius_m": 500.0,
            "collision_radius_m": 1.0,
            "lookahead_seconds": 4.0,
            "max_operations_per_tick": 1,
            "max_active_cells": 1,
            "approach_offset_m": 600.0,
            "approach_speed_mps": 100.0,
            "far_offset_m": 900.0,
            "max_load_frames": 180,
            "settle_frames": 4,
        },
        "policy": {
            "sealed_candidate_direct_QA_registration": True,
            "production_runtime_index_used": False,
            "production_runtime_index_mutated": False,
            "collision_gate_is_separate": True,
            "runtime_mount_authorized": False,
            "runtime_promotion_allowed": False,
        },
    }
    probe["probe_digest"] = _digest(probe)
    return probe


def _validate_probe(probe: dict[str, Any]) -> str:
    if probe.get("format") != PROBE_FORMAT or probe.get("crs") != CRS or probe.get("engine_version") != ENGINE_VERSION:
        raise ValueError("unsupported streaming probe contract")
    cell_id = probe.get("cell_id")
    if not isinstance(cell_id, str) or not cell_id.startswith("bxl-"):
        raise ValueError("streaming probe cell identity missing")
    expected = _require_sha("streaming probe digest", probe.get("probe_digest"))
    view = copy.deepcopy(probe)
    view.pop("probe_digest", None)
    if _digest(view) != expected:
        raise ValueError("streaming probe digest mismatch")
    return cell_id


def finalize(probe_path: Path, result_path: Path) -> dict[str, Any]:
    probe = _read(probe_path)
    cell_id = _validate_probe(probe)
    result = _read(result_path)
    if result.get("format") != RESULT_FORMAT or result.get("cell_id") != cell_id:
        raise ValueError("Godot streaming result identity/format mismatch")
    if result.get("probe_digest") != probe.get("probe_digest"):
        raise ValueError("Godot streaming result is stale against exact probe")
    if result.get("engine_version") != ENGINE_VERSION:
        raise ValueError("Godot streaming result engine drift")
    metrics = result.get("metrics")
    if not isinstance(metrics, dict):
        raise ValueError("Godot streaming result metrics missing")

    required_true = (
        "descriptor_registered",
        "predictive_prefetch_outside_load_radius",
        "first_load_completed",
        "runtime_cell_id_match",
        "street_surface_count_match",
        "building_accounting_match",
        "first_unload_completed",
        "second_load_completed",
        "warm_cache_reused",
        "final_unload_completed",
        "production_index_used_false",
        "collision_claimed_false",
    )
    checks = {name: metrics.get(name) is True for name in required_true}
    checks.update({
        "load_count_two": int(metrics.get("backend_load_count", -1)) == 2,
        "unload_count_two": int(metrics.get("backend_unload_count", -1)) == 2,
        "failed_load_zero": int(metrics.get("backend_failed_load_count", -1)) == 0,
        "duplicate_activation_zero": int(metrics.get("duplicate_activation_attempts", -1)) == 0,
        "collision_enable_zero": int(metrics.get("collision_enable_count", -1)) == 0,
        "cache_miss_one": int(metrics.get("cache_misses", -1)) == 1,
        "cache_hit_at_least_one": int(metrics.get("cache_hits", -1)) >= 1,
        "cache_unreferenced_final": int(metrics.get("cache_referenced_entries", -1)) == 0,
    })
    passed = result.get("passed") is True and all(checks.values())
    status = "passed_godot_4_7_1_generic_candidate_streaming" if passed else "failed_godot_4_7_1_generic_candidate_streaming"
    row = {
        "cell_id": cell_id,
        "gate": "streaming",
        "passed": passed,
        "status": status,
        "source": "godot_4_7_1_generic_sealed_candidate_streaming_probe",
        "metrics": {
            "contract_checks": checks,
            "engine_result_status": result.get("status"),
            **copy.deepcopy(metrics),
        },
    }
    row["measurement_digest"] = _digest(row)
    bundle = {
        "format": MEASUREMENT_FORMAT,
        "cell_id": cell_id,
        "crs": CRS,
        "bindings": copy.deepcopy(probe["bindings"]),
        "gates": {"streaming": row},
        "policy": {
            "production_runtime_index_used": False,
            "production_runtime_index_mutated": False,
            "collision_gate_is_separate": True,
            "runtime_promotion_allowed": False,
        },
    }
    bundle["measurement_bundle_digest"] = _digest(bundle)
    return bundle


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    prep = sub.add_parser("prepare")
    prep.add_argument("--terrain-lod", type=Path, required=True)
    prep.add_argument("--terrain-runtime-candidate", type=Path, required=True)
    prep.add_argument("--secondary-height-validation", type=Path, required=True)
    prep.add_argument("--runtime-candidate", type=Path, required=True)
    prep.add_argument("--candidate-dir", type=Path, required=True)
    prep.add_argument("--candidate-resource-root", required=True)
    prep.add_argument("--output", type=Path, required=True)
    fin = sub.add_parser("finalize")
    fin.add_argument("--probe", type=Path, required=True)
    fin.add_argument("--godot-result", type=Path, required=True)
    fin.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.command == "prepare":
            result = prepare(args.terrain_lod, args.terrain_runtime_candidate, args.secondary_height_validation, args.runtime_candidate, args.candidate_dir, args.candidate_resource_root)
            label = f"TERRAIN_STREAMING_PROBE_OK cell={result['cell_id']} production_index=false runtime_promotion=false"
        else:
            result = finalize(args.probe, args.godot_result)
            row = result["gates"]["streaming"]
            label = f"TERRAIN_STREAMING_GATE_OK cell={result['cell_id']} passed={str(row['passed']).lower()} production_index=false runtime_promotion=false"
    except Exception as exc:
        print(f"TERRAIN_STREAMING_GATE_ERROR: {exc}")
        return 1
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(label)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
