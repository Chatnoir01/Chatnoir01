#!/usr/bin/env python3
"""Validate exact render/collision parity for the five validated Ixelles 2 m DTM cells.

Evidence only. Both candidate surfaces are generated independently from the same
locked UrbIS DTM 2021 float64 grids on the global EPSG:31370 2 m lattice. This
proves a source-space collision contract; it does not mount or approve runtime
terrain in Godot.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np

from measure_ixelles_dtm_2m_seams import CELLS, SOURCE_ARCHIVES, SPACING_M, make_grid, open_mosaic


def build_index_buffer(rows: int, cols: int) -> np.ndarray:
    if rows < 2 or cols < 2:
        raise ValueError("grid must contain at least one quad")
    triangles = np.empty(((rows - 1) * (cols - 1) * 2, 3), dtype=np.int64)
    out = 0
    for r in range(rows - 1):
        base = r * cols
        next_base = (r + 1) * cols
        for c in range(cols - 1):
            sw = base + c
            se = sw + 1
            nw = next_base + c
            ne = nw + 1
            triangles[out] = (sw, nw, se)
            triangles[out + 1] = (se, nw, ne)
            out += 2
    return triangles


def build_vertices(grid: np.ndarray, west: float, south: float, spacing_m: float) -> np.ndarray:
    rows, cols = grid.shape
    xs = west + np.arange(cols, dtype=np.float64) * spacing_m
    ys = south + np.arange(rows, dtype=np.float64) * spacing_m
    yy, xx = np.meshgrid(ys, xs, indexing="ij")
    return np.column_stack((xx.reshape(-1), yy.reshape(-1), grid.reshape(-1))).astype(np.float64, copy=False)


def _sha256_array(array: np.ndarray, dtype: str) -> str:
    normalized = np.ascontiguousarray(array.astype(dtype, copy=False))
    return hashlib.sha256(normalized.tobytes()).hexdigest()


def compare_surface_collision(render_grid: np.ndarray, collision_grid: np.ndarray, *, west: float, south: float, spacing_m: float) -> dict:
    if render_grid.shape != collision_grid.shape:
        raise ValueError(f"render/collision shape mismatch: {render_grid.shape} vs {collision_grid.shape}")
    if render_grid.ndim != 2:
        raise ValueError("render/collision grids must be 2D")
    if not np.all(np.isfinite(render_grid)) or not np.all(np.isfinite(collision_grid)):
        raise ValueError("render/collision grids contain non-finite samples")

    render_vertices = build_vertices(render_grid, west, south, spacing_m)
    collision_vertices = build_vertices(collision_grid, west, south, spacing_m)
    render_indices = build_index_buffer(*render_grid.shape)
    collision_indices = build_index_buffer(*collision_grid.shape)

    z_delta = np.abs(render_vertices[:, 2] - collision_vertices[:, 2])
    xy_delta = np.abs(render_vertices[:, :2] - collision_vertices[:, :2])
    max_z = float(np.max(z_delta)) if z_delta.size else 0.0
    max_xy = float(np.max(xy_delta)) if xy_delta.size else 0.0
    nonzero_z = int(np.count_nonzero(z_delta))
    nonzero_xy = int(np.count_nonzero(xy_delta))
    indices_equal = bool(np.array_equal(render_indices, collision_indices))

    render_vertex_sha = _sha256_array(render_vertices, "<f8")
    collision_vertex_sha = _sha256_array(collision_vertices, "<f8")
    render_index_sha = _sha256_array(render_indices, "<i8")
    collision_index_sha = _sha256_array(collision_indices, "<i8")

    passed = bool(max_z == 0.0 and max_xy == 0.0 and nonzero_z == 0 and nonzero_xy == 0 and indices_equal and render_vertex_sha == collision_vertex_sha and render_index_sha == collision_index_sha)
    return {
        "vertex_count": int(render_vertices.shape[0]),
        "triangle_count": int(render_indices.shape[0]),
        "max_abs_vertex_z_delta_m": max_z,
        "max_abs_vertex_xy_delta_m": max_xy,
        "nonzero_vertex_z_delta_count": nonzero_z,
        "nonzero_vertex_xy_delta_count": nonzero_xy,
        "indices_equal": indices_equal,
        "render_vertex_sha256": render_vertex_sha,
        "collision_vertex_sha256": collision_vertex_sha,
        "render_index_sha256": render_index_sha,
        "collision_index_sha256": collision_index_sha,
        "collision_parity_pass": passed,
    }


def measure(paths: list[Path], archive_hashes: dict[str, str]) -> dict:
    array, transform, crs_origins = open_mosaic(paths)
    cells_out = []
    total_vertices = 0
    total_triangles = 0
    failures = 0
    for cell_id, bbox in CELLS:
        west, south, _east, _north = bbox
        render_grid = make_grid(array, transform, bbox)
        collision_grid = make_grid(array, transform, bbox)
        parity = compare_surface_collision(render_grid, collision_grid, west=west, south=south, spacing_m=SPACING_M)
        total_vertices += parity["vertex_count"]
        total_triangles += parity["triangle_count"]
        failures += 0 if parity["collision_parity_pass"] else 1
        cells_out.append({"cell_id": cell_id, "bbox_epsg31370": list(bbox), **parity})

    max_z = max(cell["max_abs_vertex_z_delta_m"] for cell in cells_out)
    max_xy = max(cell["max_abs_vertex_xy_delta_m"] for cell in cells_out)
    nonzero_z = sum(cell["nonzero_vertex_z_delta_count"] for cell in cells_out)
    nonzero_xy = sum(cell["nonzero_vertex_xy_delta_count"] for cell in cells_out)
    gate = bool(failures == 0 and max_z == 0.0 and max_xy == 0.0 and nonzero_z == 0 and nonzero_xy == 0)
    return {
        "schema": "grand-bruxelles-ixelles-dtm-2m-collision-parity-v1",
        "dataset": "Paradigm / Brussels-Capital Region UrbIS Digital Terrain Model 2021",
        "source_crs": "EPSG:31370",
        "source_crs_origin": crs_origins,
        "source_archive_sha256": archive_hashes,
        "candidate_resolution_m": SPACING_M,
        "render_candidate": "independent triangle mesh generated from the locked float64 2 m DTM grid",
        "collision_candidate": "independent triangle mesh generated from the same locked float64 2 m DTM grid",
        "triangle_winding_contract": "two deterministic triangles per 2 m quad: SW-NW-SE and SE-NW-NE",
        "runtime_approved": False,
        "promote_runtime": False,
        "cells": cells_out,
        "aggregate": {
            "cell_count": len(cells_out),
            "vertices_total_before_cross_cell_dedup": total_vertices,
            "triangles_total": total_triangles,
            "failed_cell_count": failures,
            "max_abs_vertex_z_delta_m": max_z,
            "max_abs_vertex_xy_delta_m": max_xy,
            "nonzero_vertex_z_delta_count": nonzero_z,
            "nonzero_vertex_xy_delta_count": nonzero_xy,
            "collision_parity_gate_pass": gate,
        },
        "status": "source_space_collision_parity_measured_runtime_not_approved",
        "limitation": "This gate proves source-space render/collision topology parity only; Godot runtime transform, PhysicsServer shape behavior, streaming and visual fidelity remain unapproved.",
        "next_gate": "validate Godot collision/runtime transform parity on these same five cells, then streaming/render cost and deterministic visual fidelity",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--raster", type=Path, nargs=2, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--archive-hash", action="append", default=[], help="tile=sha256")
    args = parser.parse_args()
    hashes = dict(item.split("=", 1) for item in args.archive_hash)
    if hashes and hashes != SOURCE_ARCHIVES:
        raise ValueError(f"Archive hashes do not match locked source: {hashes}")
    result = measure(args.raster, hashes or SOURCE_ARCHIVES)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    agg = result["aggregate"]
    print("IXELLES_DTM_2M_COLLISION_PARITY", json.dumps(agg, sort_keys=True))
    return 0 if agg["collision_parity_gate_pass"] else 2


if __name__ == "__main__":
    raise SystemExit(main())