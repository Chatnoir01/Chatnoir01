#!/usr/bin/env python3
"""Materialize source-faithful 2 m DTM candidates for the streamed Ixelles neighbors.

The official absolute DTM stays authoritative. Every generated cell uses the one
already-shipped seed vertical datum, so source-perfect seams remain vertically
continuous in Godot. This tool does not approve runtime terrain.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

import numpy as np

from measure_ixelles_dtm_2m_seams import CELLS, SOURCE_ARCHIVES, SPACING_M, make_grid, open_mosaic

SCHEMA = "grand-bruxelles-ixelles-dtm-2m-runtime-candidate-v1"
TARGET_IDS = (
    "bxl-e149000-n169500-s500",
    "bxl-e149500-n169000-s500",
    "bxl-e149500-n169500-s500",
)
SEED_ID = "bxl-e149000-n169000-s500"
EXPECTED_REFERENCE_M = 62.393423


def sha256_float64(values: np.ndarray) -> str:
    return hashlib.sha256(np.ascontiguousarray(values.astype("<f8", copy=False)).tobytes()).hexdigest()


def load_seed(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("cell_id") != SEED_ID:
        raise ValueError("seed cell id mismatch")
    if payload.get("bbox_epsg31370") != [149000.0, 169000.0, 149500.0, 169500.0]:
        raise ValueError("seed bbox mismatch")
    heights = payload.get("heights_row_major_m")
    if not isinstance(heights, list) or len(heights) != 63001:
        raise ValueError("seed 2 m height grid missing")
    if abs(float(heights[0]) - EXPECTED_REFERENCE_M) > 0.0000005:
        raise ValueError("seed vertical reference drifted")
    return payload


def load_datum(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("schema") != "grand-bruxelles-ixelles-shared-vertical-datum-v1":
        raise ValueError("shared datum schema mismatch")
    if payload.get("seed_cell_id") != SEED_ID:
        raise ValueError("shared datum seed mismatch")
    if abs(float(payload.get("reference_absolute_m")) - EXPECTED_REFERENCE_M) > 0.0000005:
        raise ValueError("shared datum value drifted")
    if payload.get("grid_row_order") != "south_to_north_increasing_lambert_northing":
        raise ValueError("shared datum row order drifted")
    if payload.get("godot_heightmap_collision_row_order") != "reverse_north_south_only":
        raise ValueError("Godot collision row-order contract drifted")
    return payload


def rounded_grid(grid: np.ndarray) -> np.ndarray:
    if grid.shape != (251, 251) or not np.all(np.isfinite(grid)):
        raise ValueError("invalid 251x251 DTM grid")
    return np.round(grid.astype(np.float64, copy=False), 6)


def build_contract(cell_id: str, bbox: tuple[float, float, float, float], grid: np.ndarray, datum: dict[str, Any]) -> dict[str, Any]:
    reference = float(datum["reference_absolute_m"])
    relative = grid - reference
    return {
        "schema": SCHEMA,
        "cell_id": cell_id,
        "bbox_epsg31370": list(bbox),
        "spacing_m": SPACING_M,
        "shape": [251, 251],
        "sample_count": int(grid.size),
        "source": {
            "dataset": "Paradigm / Brussels-Capital Region UrbIS Digital Terrain Model 2021",
            "crs": "EPSG:31370",
            "source_archive_sha256": SOURCE_ARCHIVES,
            "sampling": "NaN-safe bilinear sampling on one global EPSG:31370 2 m lattice; values rounded to 1e-6 m for deterministic game contract",
        },
        "shared_vertical_datum": {
            "schema": datum["schema"],
            "seed_cell_id": datum["seed_cell_id"],
            "reference_absolute_m": reference,
            "game_height_formula": datum["game_height_formula"],
        },
        "absolute_min_m": round(float(np.min(grid)), 6),
        "absolute_max_m": round(float(np.max(grid)), 6),
        "relative_min_m": round(float(np.min(relative)), 6),
        "relative_max_m": round(float(np.max(relative)), 6),
        "absolute_float64_sha256": sha256_float64(grid),
        "relative_float64_sha256": sha256_float64(relative),
        "heights_row_major_m": grid.reshape(-1).tolist(),
        "runtime_approved": False,
        "promote_runtime": False,
        "purpose": "source-faithful neighbor terrain candidate using the already-shipped Ixelles vertical datum",
    }


def edge(grid: np.ndarray, side: str) -> np.ndarray:
    if side == "north": return grid[-1, :]
    if side == "south": return grid[0, :]
    if side == "east": return grid[:, -1]
    if side == "west": return grid[:, 0]
    raise ValueError(side)


def validate_seed_and_seams(grids: dict[str, np.ndarray], seed_payload: dict[str, Any], reference: float) -> dict[str, Any]:
    seed_committed = np.array(seed_payload["heights_row_major_m"], dtype=np.float64).reshape(251, 251)
    source_seed = grids[SEED_ID]
    seed_delta = np.abs(seed_committed - source_seed)
    max_seed_delta = float(np.max(seed_delta))
    if max_seed_delta > 0.0000005:
        raise ValueError(f"generated official seed grid drifted from committed runtime seed by {max_seed_delta} m")

    checks = [
        (SEED_ID, "north", "bxl-e149000-n169500-s500", "south"),
        (SEED_ID, "east", "bxl-e149500-n169000-s500", "west"),
        ("bxl-e149000-n169500-s500", "east", "bxl-e149500-n169500-s500", "west"),
        ("bxl-e149500-n169000-s500", "north", "bxl-e149500-n169500-s500", "south"),
    ]
    seams = []
    for a_id, a_side, b_id, b_side in checks:
        a = edge(seed_committed if a_id == SEED_ID else grids[a_id], a_side)
        b = edge(grids[b_id], b_side)
        abs_delta = np.abs(a - b)
        relative_delta = np.abs((a - reference) - (b - reference))
        max_abs = float(np.max(abs_delta))
        max_rel = float(np.max(relative_delta))
        if max_abs != 0.0 or max_rel != 0.0:
            raise ValueError(f"shared datum seam mismatch {a_id}/{b_id}: absolute={max_abs}, relative={max_rel}")
        seams.append({
            "a": a_id, "a_side": a_side, "b": b_id, "b_side": b_side,
            "paired_samples": 251,
            "max_abs_absolute_delta_m": max_abs,
            "max_abs_relative_delta_m": max_rel,
        })
    return {
        "seed_grid_max_abs_delta_m": max_seed_delta,
        "shared_edge_count": len(seams),
        "shared_edge_pairs": len(seams) * 251,
        "max_abs_shared_edge_delta_m": max(item["max_abs_absolute_delta_m"] for item in seams),
        "max_relative_shared_edge_delta_m": max(item["max_abs_relative_delta_m"] for item in seams),
        "seams": seams,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--raster", type=Path, nargs=2, required=True)
    parser.add_argument("--seed", type=Path, required=True)
    parser.add_argument("--datum", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()

    seed_payload = load_seed(args.seed)
    datum = load_datum(args.datum)
    array, transform, _crs_origins = open_mosaic(args.raster)
    cell_map = dict(CELLS)
    grids = {cell_id: rounded_grid(make_grid(array, transform, bbox)) for cell_id, bbox in CELLS}
    report = validate_seed_and_seams(grids, seed_payload, float(datum["reference_absolute_m"]))

    args.output_dir.mkdir(parents=True, exist_ok=True)
    outputs = {}
    for cell_id in TARGET_IDS:
        contract = build_contract(cell_id, cell_map[cell_id], grids[cell_id], datum)
        path = args.output_dir / f"{cell_id}_dtm_2m.game.json"
        path.write_text(json.dumps(contract, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
        outputs[cell_id] = {
            "absolute_float64_sha256": contract["absolute_float64_sha256"],
            "relative_float64_sha256": contract["relative_float64_sha256"],
            "min_m": contract["absolute_min_m"],
            "max_m": contract["absolute_max_m"],
        }

    result = {
        "schema": "grand-bruxelles-ixelles-shared-datum-neighbor-dtm-report-v1",
        "reference_absolute_m": float(datum["reference_absolute_m"]),
        "seed_cell_id": SEED_ID,
        "target_cells": list(TARGET_IDS),
        "source_archive_sha256": SOURCE_ARCHIVES,
        "validation": report,
        "outputs": outputs,
        "runtime_approved": False,
        "promote_runtime": False,
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("IXELLES_SHARED_DATUM_NEIGHBOR_DTM", json.dumps({
        "reference_absolute_m": result["reference_absolute_m"],
        "target_cells": 3,
        "seed_grid_max_abs_delta_m": report["seed_grid_max_abs_delta_m"],
        "shared_edge_pairs": report["shared_edge_pairs"],
        "max_abs_shared_edge_delta_m": report["max_abs_shared_edge_delta_m"],
        "max_relative_shared_edge_delta_m": report["max_relative_shared_edge_delta_m"],
        "runtime_approved": False,
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
