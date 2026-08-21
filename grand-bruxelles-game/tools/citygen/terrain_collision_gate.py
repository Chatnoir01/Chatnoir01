#!/usr/bin/env python3
"""Prepare and finalize an exact per-cell Godot HeightMapShape3D collision probe.

The prepare phase verifies the same four artifact bindings used by terrain runtime
readiness, decodes the exact QA terrain candidate and writes an ephemeral Godot
probe manifest. The finalize phase converts a Godot 4.7.1 physics result into a
normal terrain runtime measurement bundle.

This module never authorizes collision generation, runtime mounting or production
promotion. A green collision measurement is QA evidence only.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
import math
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent


def _load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot import {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


geometry_mod = _load_module("terrain_geometry_gates_for_collision", HERE / "measure_terrain_geometry_gates.py")
readiness_mod = _load_module("terrain_readiness_for_collision", HERE / "build_terrain_runtime_readiness.py")

PROBE_FORMAT = "grand-bruxelles-terrain-collision-godot-probe-v1"
RESULT_FORMAT = "grand-bruxelles-terrain-collision-godot-result-v1"
MEASUREMENT_FORMAT = "grand-bruxelles-terrain-runtime-gate-measurement-bundle-v1"
CRS = readiness_mod.CRS
ENGINE_VERSION = "4.7.1"
RAYCAST_TOLERANCE_M = 0.10


def _read(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def _digest(value: Any) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def _verify_probe_digest(probe: dict[str, Any]) -> str:
    expected = probe.get("probe_digest")
    if not isinstance(expected, str) or len(expected) != 64:
        raise ValueError("collision probe digest missing")
    view = copy.deepcopy(probe)
    view.pop("probe_digest", None)
    if _digest(view) != expected:
        raise ValueError("collision probe digest mismatch")
    return expected


def _bindings(
    terrain: dict[str, Any],
    terrain_candidate: dict[str, Any],
    secondary: dict[str, Any],
    runtime_candidate: dict[str, Any],
) -> tuple[str, dict[str, str]]:
    cell_id, terrain_digest, terrain_candidate_digest, secondary_digest, runtime_digest = readiness_mod._validate_base(
        terrain, terrain_candidate, secondary, runtime_candidate
    )
    return cell_id, {
        "terrain_lod_evidence_digest": terrain_digest,
        "terrain_runtime_candidate_digest": terrain_candidate_digest,
        "secondary_height_validation_digest": secondary_digest,
        "runtime_candidate_digest": runtime_digest,
    }


def _sample_positions(rows: int, cols: int) -> list[tuple[int, int]]:
    """Return deterministic asymmetric samples that can detect mirroring/transposition.

    A center-only ray can pass even if row orientation is wrong because min/max and
    the center sample are invariant under several permutations. Include four
    interior/corner-biased samples plus center, deduplicated for tiny grids.
    """
    candidates = [
        (rows // 2, cols // 2),
        (0, 0),
        (0, cols - 1),
        (rows - 1, 0),
        (rows - 1, cols - 1),
    ]
    result: list[tuple[int, int]] = []
    seen: set[tuple[int, int]] = set()
    for row, col in candidates:
        key = (int(row), int(col))
        if key in seen:
            continue
        seen.add(key)
        result.append(key)
    return result


def prepare(
    terrain_path: Path,
    terrain_candidate_path: Path,
    secondary_path: Path,
    runtime_candidate_path: Path,
) -> dict[str, Any]:
    import numpy as np

    terrain = _read(terrain_path)
    terrain_candidate = _read(terrain_candidate_path)
    secondary = _read(secondary_path)
    runtime_candidate = _read(runtime_candidate_path)
    cell_id, bindings = _bindings(terrain, terrain_candidate, secondary, runtime_candidate)
    grid, bbox, spacing, verified_digest = geometry_mod._validate_candidate(terrain_candidate, cell_id)
    if verified_digest != bindings["terrain_runtime_candidate_digest"]:
        raise ValueError("verified terrain candidate digest differs from collision binding")

    rows, cols = grid.shape
    if rows < 2 or cols < 2:
        raise ValueError("heightmap collision probe requires at least a 2x2 grid")
    if not np.all(np.isfinite(grid)):
        raise ValueError("heightmap collision probe contains non-finite source heights")

    # Candidate rows increase northing while Godot world Z decreases with northing.
    # Reverse row order before flattening so increasing HeightMapShape3D depth maps to
    # increasing game-world Z without altering any height sample.
    godot_grid = np.flipud(np.asarray(grid, dtype=np.float64))
    flattened = [round(float(value), 6) for value in godot_grid.reshape(-1)]
    if len(flattened) != rows * cols:
        raise ValueError("heightmap collision probe sample count mismatch")

    raycast_samples: list[dict[str, Any]] = []
    for sample_id, (sample_row, sample_col) in enumerate(_sample_positions(rows, cols)):
        sample_index = sample_row * cols + sample_col
        local_x = (sample_col - (cols - 1) / 2.0) * spacing
        local_z = (sample_row - (rows - 1) / 2.0) * spacing
        expected_y = flattened[sample_index]
        raycast_samples.append(
            {
                "sample_id": sample_id,
                "row": int(sample_row),
                "column": int(sample_col),
                "local_x_m": round(float(local_x), 6),
                "local_z_m": round(float(local_z), 6),
                "expected_height_m": round(float(expected_y), 6),
                "maximum_abs_error_m": RAYCAST_TOLERANCE_M,
            }
        )
    if len(raycast_samples) < 4:
        raise ValueError("heightmap collision probe requires at least four unique orientation samples")

    result: dict[str, Any] = {
        "format": PROBE_FORMAT,
        "cell_id": cell_id,
        "crs": CRS,
        "bindings": bindings,
        "bbox_epsg31370": [float(value) for value in bbox],
        "spacing_m": spacing,
        "map_width": int(cols),
        "map_depth": int(rows),
        "map_data": flattened,
        "decoded_height_min_m": round(float(np.min(godot_grid)), 6),
        "decoded_height_max_m": round(float(np.max(godot_grid)), 6),
        # Keep the legacy center sample for diagnostics, but authorization now
        # requires every entry in raycast_samples.
        "raycast_sample": raycast_samples[0],
        "raycast_samples": raycast_samples,
        "engine_contract": {
            "engine": "Godot",
            "version": ENGINE_VERSION,
            "shape": "HeightMapShape3D",
            "physics_body": "StaticBody3D",
            "physics_query": "PhysicsRayQueryParameters3D",
        },
        "policy": {
            "qa_probe_only": True,
            "rows_reversed_for_godot_world_z": True,
            "asymmetric_multi_sample_orientation_proof": True,
            "source_heights_are_not_invented": True,
            "collision_authorized": False,
            "runtime_mount_authorized": False,
            "runtime_promotion_allowed": False,
        },
    }
    result["probe_digest"] = _digest(result)
    return result


def finalize(probe_path: Path, godot_result_path: Path) -> dict[str, Any]:
    probe = _read(probe_path)
    raw = _read(godot_result_path)
    probe_digest = _verify_probe_digest(probe)
    if probe.get("format") != PROBE_FORMAT or probe.get("crs") != CRS:
        raise ValueError("unsupported terrain collision probe")
    cell_id = probe.get("cell_id")
    bindings = probe.get("bindings")
    if not isinstance(cell_id, str) or not isinstance(bindings, dict):
        raise ValueError("terrain collision probe identity/bindings missing")

    if raw.get("format") != RESULT_FORMAT:
        raise ValueError("unsupported Godot terrain collision result")
    if raw.get("cell_id") != cell_id or raw.get("probe_digest") != probe_digest:
        raise ValueError("Godot collision result is stale against exact probe")
    if raw.get("engine_version") != ENGINE_VERSION:
        raise ValueError("Godot collision result engine version mismatch")
    if not isinstance(raw.get("passed"), bool) or not isinstance(raw.get("status"), str):
        raise ValueError("Godot collision result missing pass/status")
    metrics = raw.get("metrics")
    if not isinstance(metrics, dict):
        raise ValueError("Godot collision result metrics missing")

    expected_width = int(probe["map_width"])
    expected_depth = int(probe["map_depth"])
    expected_count = expected_width * expected_depth
    expected_min = float(probe["decoded_height_min_m"])
    expected_max = float(probe["decoded_height_max_m"])
    expected_samples = probe.get("raycast_samples")
    actual_samples = metrics.get("raycast_samples")
    if not isinstance(expected_samples, list) or len(expected_samples) < 4:
        raise ValueError("collision probe missing asymmetric raycast samples")
    if not isinstance(actual_samples, list):
        actual_samples = []

    samples_match = len(actual_samples) == len(expected_samples)
    sample_checks: list[dict[str, Any]] = []
    for index, expected in enumerate(expected_samples):
        actual = actual_samples[index] if index < len(actual_samples) and isinstance(actual_samples[index], dict) else {}
        tolerance = float(expected["maximum_abs_error_m"])
        error_raw = actual.get("abs_error_m")
        error = float(error_raw) if isinstance(error_raw, (int, float)) else math.inf
        check = {
            "sample_id_matches": actual.get("sample_id") == expected.get("sample_id"),
            "row_matches": actual.get("row") == expected.get("row"),
            "column_matches": actual.get("column") == expected.get("column"),
            "expected_height_matches": isinstance(actual.get("expected_height_m"), (int, float))
            and abs(float(actual["expected_height_m"]) - float(expected["expected_height_m"])) <= 0.000001,
            "raycast_hit": actual.get("hit") is True,
            "raycast_error_within_tolerance": math.isfinite(error) and error <= tolerance,
        }
        sample_checks.append({"sample_id": expected.get("sample_id"), "checks": check})
        samples_match = samples_match and all(check.values())

    contract_checks = {
        "map_width_matches": metrics.get("map_width") == expected_width,
        "map_depth_matches": metrics.get("map_depth") == expected_depth,
        "map_data_count_matches": metrics.get("map_data_count") == expected_count,
        "shape_created": metrics.get("shape_created") is True,
        "shape_rid_valid": metrics.get("shape_rid_valid") is True,
        "body_inside_tree": metrics.get("body_inside_tree") is True,
        "all_asymmetric_raycast_samples_match": samples_match,
        "min_height_matches": isinstance(metrics.get("shape_min_height_m"), (int, float))
        and abs(float(metrics["shape_min_height_m"]) - expected_min) <= 0.001,
        "max_height_matches": isinstance(metrics.get("shape_max_height_m"), (int, float))
        and abs(float(metrics["shape_max_height_m"]) - expected_max) <= 0.001,
    }
    passed = raw["passed"] is True and all(contract_checks.values())
    status = "passed_godot_4_7_1_heightmap_shape_multiraycast" if passed else "failed_godot_heightmap_collision_probe"

    row: dict[str, Any] = {
        "cell_id": cell_id,
        "gate": "collisions",
        "passed": passed,
        "status": status,
        "source": "godot_4_7_1_heightmapshape3d_headless_exact_candidate",
        "metrics": {
            "probe_digest": probe_digest,
            "map_width": expected_width,
            "map_depth": expected_depth,
            "map_data_count": expected_count,
            "spacing_m": probe["spacing_m"],
            "raycast_sample_count": len(expected_samples),
            "godot_result_status": raw["status"],
            "godot_metrics": metrics,
            "sample_checks": sample_checks,
            "contract_checks": contract_checks,
        },
    }
    row["measurement_digest"] = _digest(row)

    bundle: dict[str, Any] = {
        "format": MEASUREMENT_FORMAT,
        "cell_id": cell_id,
        "crs": CRS,
        "bindings": bindings,
        "gates": {"collisions": row},
        "policy": {
            "measured_gates": ["collisions"],
            "exact_terrain_candidate_probe_required": True,
            "godot_engine_version_locked": ENGINE_VERSION,
            "physical_raycast_required": True,
            "asymmetric_multi_sample_orientation_proof_required": True,
            "collision_authorized": False,
            "runtime_mount_authorized": False,
            "runtime_promotion_allowed": False,
        },
    }
    bundle["measurement_bundle_digest"] = _digest(bundle)
    return bundle


def _write(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)

    prepare_parser = sub.add_parser("prepare")
    prepare_parser.add_argument("--terrain-lod", type=Path, required=True)
    prepare_parser.add_argument("--terrain-runtime-candidate", type=Path, required=True)
    prepare_parser.add_argument("--secondary-height-validation", type=Path, required=True)
    prepare_parser.add_argument("--runtime-candidate", type=Path, required=True)
    prepare_parser.add_argument("--output", type=Path, required=True)

    finalize_parser = sub.add_parser("finalize")
    finalize_parser.add_argument("--probe", type=Path, required=True)
    finalize_parser.add_argument("--godot-result", type=Path, required=True)
    finalize_parser.add_argument("--output", type=Path, required=True)

    args = parser.parse_args()
    try:
        if args.command == "prepare":
            payload = prepare(
                args.terrain_lod,
                args.terrain_runtime_candidate,
                args.secondary_height_validation,
                args.runtime_candidate,
            )
            _write(args.output, payload)
            print(
                "TERRAIN_COLLISION_PROBE_PREPARED "
                f"cell={payload['cell_id']} shape={payload['map_width']}x{payload['map_depth']} "
                f"samples={len(payload['raycast_samples'])} collision_authorized=false"
            )
        else:
            payload = finalize(args.probe, args.godot_result)
            _write(args.output, payload)
            row = payload["gates"]["collisions"]
            print(
                "TERRAIN_COLLISION_MEASUREMENT_OK "
                f"cell={payload['cell_id']} passed={str(row['passed']).lower()} "
                f"samples={row['metrics']['raycast_sample_count']} runtime_promotion=false"
            )
    except Exception as exc:
        print(f"TERRAIN_COLLISION_GATE_ERROR: {exc}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())