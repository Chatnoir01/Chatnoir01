#!/usr/bin/env python3
"""Measure terrain seams and normal health against exact QA terrain candidates.

This is evidence-only. It never authorizes collisions, runtime mounting or
production promotion. Missing expected regional neighbours remain pending.
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


candidate_mod = _load_module("terrain_candidate", HERE / "build_cell_terrain_runtime_candidate.py")
readiness_mod = _load_module("terrain_readiness", HERE / "build_terrain_runtime_readiness.py")

FORMAT = "grand-bruxelles-terrain-runtime-gate-measurement-bundle-v1"
TARGET_FORMAT = "grand-bruxelles-regional-target-grid-v1"
CRS = "EPSG:31370"
SEAM_MAX_DELTA_M = 0.010001
MAX_NONDEGENERATE_SLOPE_DEG = 89.0


def _read(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def _digest(value: Any) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def _finalize_gate(row: dict[str, Any]) -> dict[str, Any]:
    result = copy.deepcopy(row)
    result["measurement_digest"] = _digest(result)
    return result


def _bbox(candidate: dict[str, Any]) -> tuple[float, float, float, float]:
    raw = candidate.get("bbox_epsg31370")
    if not isinstance(raw, list) or len(raw) != 4 or not all(isinstance(v, (int, float)) for v in raw):
        raise ValueError("terrain candidate bbox missing")
    bbox = tuple(float(v) for v in raw)
    if not (bbox[0] < bbox[2] and bbox[1] < bbox[3]):
        raise ValueError("terrain candidate bbox invalid")
    return bbox


def _candidate_digest(candidate: dict[str, Any]) -> str:
    expected = candidate.get("candidate_digest")
    if not isinstance(expected, str) or len(expected) != 64:
        raise ValueError("terrain candidate digest missing")
    view = copy.deepcopy(candidate)
    view.pop("candidate_digest", None)
    encoding = view.get("height_encoding")
    if not isinstance(encoding, dict):
        raise ValueError("terrain candidate height encoding missing")
    encoding.pop("payload_base64", None)
    actual = candidate_mod._digest(view)
    if actual != expected:
        raise ValueError("terrain candidate digest mismatch")
    return expected


def _validate_candidate(candidate: dict[str, Any], expected_cell_id: str | None = None) -> tuple[Any, tuple[float, float, float, float], float, str]:
    import numpy as np

    if candidate.get("format") != candidate_mod.FORMAT or candidate.get("crs") != CRS:
        raise ValueError("unsupported terrain runtime candidate")
    cell_id = candidate.get("cell_id")
    if not isinstance(cell_id, str) or not cell_id.startswith("bxl-"):
        raise ValueError("terrain candidate cell identity missing")
    if expected_cell_id is not None and cell_id != expected_cell_id:
        raise ValueError("terrain candidate cell identity mismatch")
    authorization = candidate.get("authorization")
    topology = candidate.get("topology")
    if not isinstance(authorization, dict) or not isinstance(topology, dict):
        raise ValueError("terrain candidate safety/topology contract missing")
    if authorization.get("candidate_only") is not True:
        raise ValueError("terrain candidate is not candidate-only")
    for flag in ("terrain_runtime_authorized", "collision_authorized", "runtime_mount_authorized", "jouable_promotion_authorized"):
        if authorization.get(flag) is not False:
            raise ValueError(f"terrain candidate unexpectedly authorizes {flag}")
    if topology.get("includes_all_four_canonical_cell_edges") is not True or topology.get("shared_edge_coordinates_are_exact") is not True:
        raise ValueError("terrain candidate canonical-edge topology missing")

    bbox = _bbox(candidate)
    spacing = float(candidate.get("spacing_m", 0.0))
    if not math.isfinite(spacing) or spacing <= 0:
        raise ValueError("terrain candidate spacing invalid")
    rows = int(round((bbox[3] - bbox[1]) / spacing)) + 1
    cols = int(round((bbox[2] - bbox[0]) / spacing)) + 1
    shape = candidate.get("shape")
    if shape != [rows, cols]:
        raise ValueError(f"terrain candidate shape does not cover canonical edges: expected={[rows, cols]} got={shape}")
    if candidate.get("sample_count") != rows * cols:
        raise ValueError("terrain candidate sample count mismatch")

    digest = _candidate_digest(candidate)
    grid = candidate_mod.decode_heightfield(candidate)
    if grid.shape != (rows, cols) or not np.all(np.isfinite(grid)):
        raise ValueError("decoded terrain grid invalid")
    return grid, bbox, spacing, digest


def _target_cells(path: Path) -> dict[str, tuple[float, float, float, float]]:
    payload = _read(path)
    if payload.get("format") != TARGET_FORMAT or payload.get("crs") != CRS:
        raise ValueError("unsupported Brussels regional target grid")
    result: dict[str, tuple[float, float, float, float]] = {}
    for row in payload.get("cells") or []:
        if not isinstance(row, dict):
            raise ValueError("target grid cell must be an object")
        cell_id = row.get("cell_id")
        raw = row.get("bbox")
        if not isinstance(cell_id, str) or not isinstance(raw, list) or len(raw) != 4:
            raise ValueError("target grid cell identity or bbox invalid")
        bbox = tuple(float(v) for v in raw)
        if cell_id in result:
            raise ValueError(f"duplicate target grid cell: {cell_id}")
        result[cell_id] = bbox
    if not result:
        raise ValueError("target grid contains no cells")
    return result


def _bbox_key(bbox: tuple[float, float, float, float]) -> tuple[float, float, float, float]:
    return tuple(round(v, 6) for v in bbox)


def _expected_neighbors(cell_id: str, bbox: tuple[float, float, float, float], targets: dict[str, tuple[float, float, float, float]]) -> dict[str, str]:
    if cell_id not in targets or _bbox_key(targets[cell_id]) != _bbox_key(bbox):
        raise ValueError("terrain candidate bbox does not match regional target grid")
    by_bbox = {_bbox_key(value): key for key, value in targets.items()}
    west, south, east, north = bbox
    width = east - west
    height = north - south
    requested = {
        "west": (west - width, south, west, north),
        "east": (east, south, east + width, north),
        "south": (west, south - height, east, south),
        "north": (west, north, east, north + height),
    }
    return {direction: by_bbox[_bbox_key(target)] for direction, target in requested.items() if _bbox_key(target) in by_bbox}


def _edge(grid: Any, direction: str) -> Any:
    if direction == "west":
        return grid[:, 0]
    if direction == "east":
        return grid[:, -1]
    if direction == "south":
        return grid[0, :]
    if direction == "north":
        return grid[-1, :]
    raise ValueError(f"unsupported edge direction: {direction}")


def _opposite(direction: str) -> str:
    return {"west": "east", "east": "west", "south": "north", "north": "south"}[direction]


def _measure_seams(
    cell_id: str,
    center_grid: Any,
    center_spacing: float,
    expected: dict[str, str],
    targets: dict[str, tuple[float, float, float, float]],
    candidate_root: Path,
) -> dict[str, Any]:
    import numpy as np

    missing: list[str] = []
    invalid: list[dict[str, str]] = []
    comparisons: list[dict[str, Any]] = []
    for direction, neighbor_id in sorted(expected.items()):
        path = candidate_root / neighbor_id / "terrain_runtime_candidate.json"
        if not path.is_file():
            missing.append(neighbor_id)
            continue
        try:
            neighbor = _read(path)
            neighbor_grid, neighbor_bbox, spacing, digest = _validate_candidate(neighbor, neighbor_id)
            target_bbox = targets.get(neighbor_id)
            if target_bbox is None or _bbox_key(neighbor_bbox) != _bbox_key(target_bbox):
                raise ValueError("neighbor terrain candidate bbox does not match regional target grid")
            if not math.isclose(spacing, center_spacing, rel_tol=0.0, abs_tol=1e-9):
                raise ValueError(f"spacing mismatch center={center_spacing} neighbor={spacing}")
            center_edge = _edge(center_grid, direction)
            neighbor_edge = _edge(neighbor_grid, _opposite(direction))
            if center_edge.shape != neighbor_edge.shape:
                raise ValueError(f"edge sample count mismatch center={center_edge.shape} neighbor={neighbor_edge.shape}")
            delta = np.abs(center_edge - neighbor_edge)
            comparisons.append({
                "direction": direction,
                "neighbor_cell_id": neighbor_id,
                "neighbor_candidate_digest": digest,
                "sample_count": int(delta.size),
                "max_abs_delta_m": round(float(np.max(delta)), 6) if delta.size else 0.0,
                "mean_abs_delta_m": round(float(np.mean(delta)), 6) if delta.size else 0.0,
            })
        except Exception as exc:
            invalid.append({"neighbor_cell_id": neighbor_id, "direction": direction, "error": str(exc)})

    max_delta = max((float(row["max_abs_delta_m"]) for row in comparisons), default=0.0)
    if invalid:
        passed = False
        status = "failed_invalid_neighbor_candidate"
    elif missing:
        passed = False
        status = "pending_neighbor_candidates"
    elif max_delta > SEAM_MAX_DELTA_M:
        passed = False
        status = "failed_shared_edge_height_delta"
    else:
        passed = True
        status = "passed_shared_edge_height_continuity" if expected else "passed_regional_boundary_no_adjacent_cells"

    return _finalize_gate({
        "cell_id": cell_id,
        "gate": "seams",
        "passed": passed,
        "status": status,
        "source": "decoded_terrain_runtime_candidates",
        "metrics": {
            "expected_neighbor_count": len(expected),
            "compared_neighbor_count": len(comparisons),
            "missing_neighbor_cell_ids": sorted(missing),
            "invalid_neighbors": invalid,
            "max_allowed_abs_delta_m": SEAM_MAX_DELTA_M,
            "max_observed_abs_delta_m": round(max_delta, 6),
            "comparisons": comparisons,
        },
    })


def _measure_normals(cell_id: str, grid: Any, spacing: float) -> dict[str, Any]:
    import numpy as np

    d_height_d_north, d_height_d_east = np.gradient(grid, spacing, spacing)
    nx = -d_height_d_east
    ny = np.ones_like(grid, dtype=np.float64)
    nz = d_height_d_north
    length = np.sqrt(nx * nx + ny * ny + nz * nz)
    finite = np.isfinite(length) & (length > 0.0)
    unit_y = np.full_like(length, np.nan, dtype=np.float64)
    unit_y[finite] = ny[finite] / length[finite]
    slope_deg = np.degrees(np.arctan(np.sqrt(d_height_d_east * d_height_d_east + d_height_d_north * d_height_d_north)))
    all_finite = bool(np.all(finite) and np.all(np.isfinite(slope_deg)) and np.all(np.isfinite(unit_y)))
    max_slope = float(np.max(slope_deg)) if slope_deg.size and np.all(np.isfinite(slope_deg)) else math.inf
    min_up = float(np.min(unit_y)) if all_finite else -math.inf
    passed = all_finite and min_up > 0.0 and max_slope < MAX_NONDEGENERATE_SLOPE_DEG
    return _finalize_gate({
        "cell_id": cell_id,
        "gate": "normals",
        "passed": passed,
        "status": "passed_finite_upward_nondegenerate_normals" if passed else "failed_degenerate_or_nonfinite_normals",
        "source": "decoded_terrain_runtime_candidate",
        "metrics": {
            "vertex_count": int(grid.size),
            "all_normals_finite": all_finite,
            "minimum_up_component": round(min_up, 9) if math.isfinite(min_up) else None,
            "maximum_slope_deg": round(max_slope, 6) if math.isfinite(max_slope) else None,
            "maximum_nondegenerate_slope_deg": MAX_NONDEGENERATE_SLOPE_DEG,
        },
    })


def measure(
    terrain_path: Path,
    terrain_candidate_path: Path,
    secondary_path: Path,
    runtime_candidate_path: Path,
    target_grid_path: Path,
    candidate_root: Path,
) -> dict[str, Any]:
    terrain = _read(terrain_path)
    terrain_candidate = _read(terrain_candidate_path)
    secondary = _read(secondary_path)
    runtime_candidate = _read(runtime_candidate_path)
    cell_id, terrain_digest, terrain_candidate_digest, secondary_digest, runtime_digest = readiness_mod._validate_base(
        terrain, terrain_candidate, secondary, runtime_candidate
    )
    grid, bbox, spacing, verified_digest = _validate_candidate(terrain_candidate, cell_id)
    if verified_digest != terrain_candidate_digest:
        raise ValueError("verified terrain candidate digest differs from readiness binding")
    targets = _target_cells(target_grid_path)
    expected = _expected_neighbors(cell_id, bbox, targets)
    gates = {
        "seams": _measure_seams(cell_id, grid, spacing, expected, targets, candidate_root),
        "normals": _measure_normals(cell_id, grid, spacing),
    }
    result = {
        "format": FORMAT,
        "cell_id": cell_id,
        "crs": CRS,
        "bindings": {
            "terrain_lod_evidence_digest": terrain_digest,
            "terrain_runtime_candidate_digest": terrain_candidate_digest,
            "secondary_height_validation_digest": secondary_digest,
            "runtime_candidate_digest": runtime_digest,
        },
        "gates": gates,
        "policy": {
            "measured_gates": ["seams", "normals"],
            "unmeasured_gates_are_not_inferred": True,
            "regional_target_grid_defines_expected_neighbors": True,
            "neighbor_candidate_bbox_must_match_target_grid": True,
            "missing_expected_neighbor_candidate_is_pending": True,
            "runtime_promotion_allowed": False,
        },
    }
    result["measurement_bundle_digest"] = _digest(result)
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--terrain-lod", type=Path, required=True)
    parser.add_argument("--terrain-runtime-candidate", type=Path, required=True)
    parser.add_argument("--secondary-height-validation", type=Path, required=True)
    parser.add_argument("--runtime-candidate", type=Path, required=True)
    parser.add_argument("--target-grid", type=Path, required=True)
    parser.add_argument("--candidate-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        result = measure(
            args.terrain_lod,
            args.terrain_runtime_candidate,
            args.secondary_height_validation,
            args.runtime_candidate,
            args.target_grid,
            args.candidate_root,
        )
    except Exception as exc:
        print(f"TERRAIN_GEOMETRY_GATES_ERROR: {exc}")
        return 1
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    seams = result["gates"]["seams"]
    normals = result["gates"]["normals"]
    print(
        "TERRAIN_GEOMETRY_GATES_OK "
        f"cell={result['cell_id']} seams={str(seams['passed']).lower()} normals={str(normals['passed']).lower()} "
        "runtime_promotion=false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
