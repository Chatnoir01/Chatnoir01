#!/usr/bin/env python3
"""Measure source-faithful 2 m DTM normal continuity on the five validated Ixelles cells.

Evidence only. Every shared-edge normal is addressed independently from each cell,
but derivatives sample the same locked UrbIS DTM mosaic on the global EPSG:31370
2 m lattice. Central differences are used wherever both +/-2 m samples exist.
At the outer boundary of the validated two-archive block only, a deterministic
one-sided 2 m derivative is used rather than inventing data outside the locked source.
Runtime remains unapproved.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np

import measure_ixelles_dtm_2m_seams as seams

SPACING_M = seams.SPACING_M
CELLS = dict(seams.CELLS)
SHARED_EDGES = seams.SHARED_EDGES
SOURCE_ARCHIVES = seams.SOURCE_ARCHIVES


def edge_coords(bbox: tuple[float, float, float, float], side: str) -> tuple[np.ndarray, np.ndarray]:
    west, south, east, north = bbox
    if side in ("north", "south"):
        xs = np.arange(west, east + SPACING_M * 0.5, SPACING_M, dtype=np.float64)
        ys = np.full(xs.shape, north if side == "north" else south, dtype=np.float64)
    elif side in ("east", "west"):
        ys = np.arange(south, north + SPACING_M * 0.5, SPACING_M, dtype=np.float64)
        xs = np.full(ys.shape, east if side == "east" else west, dtype=np.float64)
    else:
        raise ValueError(side)
    if xs.size != 251 or ys.size != 251:
        raise AssertionError(f"Expected 251 shared-edge positions, got {xs.size}/{ys.size}")
    return xs, ys


def _axis_derivative(
    array: np.ndarray,
    transform,
    xs: np.ndarray,
    ys: np.ndarray,
    axis: str,
) -> tuple[np.ndarray, np.ndarray]:
    """Return dz/daxis and method code: 0 central, -1 backward, +1 forward.

    One-sided fallback is allowed only when the opposite source sample is finite.
    This keeps the computation inside the two locked source archives and makes the
    boundary policy explicit instead of clamping a per-cell derivative.
    """
    center = seams.bilinear_sample(array, transform, xs, ys)
    if axis == "x":
        minus = seams.bilinear_sample(array, transform, xs - SPACING_M, ys)
        plus = seams.bilinear_sample(array, transform, xs + SPACING_M, ys)
    elif axis == "y":
        minus = seams.bilinear_sample(array, transform, xs, ys - SPACING_M)
        plus = seams.bilinear_sample(array, transform, xs, ys + SPACING_M)
    else:
        raise ValueError(axis)

    if not np.all(np.isfinite(center)):
        raise ValueError(f"Non-finite center samples for {axis} derivative")

    derivative = np.full(center.shape, np.nan, dtype=np.float64)
    method = np.full(center.shape, 99, dtype=np.int8)

    central = np.isfinite(minus) & np.isfinite(plus)
    derivative[central] = (plus[central] - minus[central]) / (2.0 * SPACING_M)
    method[central] = 0

    forward = ~central & ~np.isfinite(minus) & np.isfinite(plus)
    derivative[forward] = (plus[forward] - center[forward]) / SPACING_M
    method[forward] = 1

    backward = ~central & np.isfinite(minus) & ~np.isfinite(plus)
    derivative[backward] = (center[backward] - minus[backward]) / SPACING_M
    method[backward] = -1

    if not np.all(np.isfinite(derivative)):
        missing = int(np.count_nonzero(~np.isfinite(derivative)))
        raise ValueError(f"Insufficient locked-source halo for {axis} derivative: {missing}")
    return derivative, method


def normals_at(array: np.ndarray, transform, xs: np.ndarray, ys: np.ndarray) -> tuple[np.ndarray, dict[str, int]]:
    dzdx, mx = _axis_derivative(array, transform, xs, ys, "x")
    dzdy, my = _axis_derivative(array, transform, xs, ys, "y")
    normals = np.stack([-dzdx, -dzdy, np.ones_like(dzdx)], axis=1)
    lengths = np.linalg.norm(normals, axis=1)
    normals = normals / lengths[:, None]
    methods = {
        "x_central": int(np.count_nonzero(mx == 0)),
        "x_forward": int(np.count_nonzero(mx == 1)),
        "x_backward": int(np.count_nonzero(mx == -1)),
        "y_central": int(np.count_nonzero(my == 0)),
        "y_forward": int(np.count_nonzero(my == 1)),
        "y_backward": int(np.count_nonzero(my == -1)),
    }
    return normals, methods


def hash_float64(values: np.ndarray) -> str:
    normalized = np.ascontiguousarray(values.astype("<f8", copy=False))
    return hashlib.sha256(normalized.tobytes()).hexdigest()


def angular_deltas_deg(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    exact = np.all(a == b, axis=1)
    out = np.zeros(a.shape[0], dtype=np.float64)
    if np.all(exact):
        return out
    dots = np.sum(a[~exact] * b[~exact], axis=1)
    denom = np.linalg.norm(a[~exact], axis=1) * np.linalg.norm(b[~exact], axis=1)
    cosines = np.clip(dots / denom, -1.0, 1.0)
    out[~exact] = np.degrees(np.arccos(cosines))
    return out


def measure(paths: list[Path], archive_hashes: dict[str, str]) -> dict:
    array, transform, crs_origins = seams.open_mosaic(paths)
    edge_results = []
    all_component_deltas = []
    all_angular_deltas = []
    total_methods = {k: 0 for k in ("x_central", "x_forward", "x_backward", "y_central", "y_forward", "y_backward")}

    for a_id, a_side, b_id, b_side in SHARED_EDGES:
        ax, ay = edge_coords(CELLS[a_id], a_side)
        bx, by = edge_coords(CELLS[b_id], b_side)
        if not (np.array_equal(ax, bx) and np.array_equal(ay, by)):
            raise ValueError(f"Shared-edge coordinates disagree: {a_id}/{b_id}")
        an, am = normals_at(array, transform, ax, ay)
        bn, bm = normals_at(array, transform, bx, by)
        if am != bm:
            raise ValueError(f"Derivative policy differs across shared edge: {a_id}/{b_id}: {am} != {bm}")
        for key, value in am.items():
            total_methods[key] += value

        component = np.max(np.abs(an - bn), axis=1)
        angular = angular_deltas_deg(an, bn)
        all_component_deltas.append(component)
        all_angular_deltas.append(angular)
        edge_results.append({
            "a": a_id,
            "a_side": a_side,
            "b": b_id,
            "b_side": b_side,
            "paired_normals": 251,
            "max_abs_component_delta": float(np.max(component)),
            "max_angular_delta_deg": float(np.max(angular)),
            "nonzero_normal_pair_count": int(np.count_nonzero(component)),
            "derivative_methods": am,
            "a_normals_sha256": hash_float64(an),
            "b_normals_sha256": hash_float64(bn),
        })

    joined_component = np.concatenate(all_component_deltas)
    joined_angular = np.concatenate(all_angular_deltas)
    max_component = float(np.max(joined_component))
    max_angle = float(np.max(joined_angular))
    nonzero_pairs = int(np.count_nonzero(joined_component))
    return {
        "schema": "grand-bruxelles-ixelles-dtm-2m-normal-continuity-v1",
        "dataset": "Paradigm / Brussels-Capital Region UrbIS Digital Terrain Model 2021",
        "source_crs": seams.EXPECTED_CRS,
        "source_crs_origin": crs_origins,
        "source_archive_sha256": archive_hashes,
        "candidate_resolution_m": SPACING_M,
        "normal_method": "global EPSG:31370 2 m finite differences: central +/-2 m where both locked-source samples exist; deterministic forward/backward 2 m derivative only at the outer boundary of the validated two-archive block",
        "runtime_contract": "shared-border vertices must address derivatives from the same global source lattice; per-cell edge-clamped normals are not approved",
        "uncertainty": "one-sided derivatives at outer-block endpoints are provisional for this five-cell validation block and may be superseded when authoritative adjacent source tiles are explicitly added; no outside-source height is invented",
        "runtime_approved": False,
        "promote_runtime": False,
        "shared_edges": edge_results,
        "aggregate": {
            "cell_count": 5,
            "shared_edge_count": 5,
            "shared_normal_pairs": int(joined_component.size),
            "max_abs_component_delta": max_component,
            "max_angular_delta_deg": max_angle,
            "nonzero_shared_normal_pair_count": nonzero_pairs,
            "derivative_method_counts_per_independent_edge_evaluation": total_methods,
            "normal_gate_pass": bool(joined_component.size == 1255 and max_component == 0.0 and max_angle == 0.0 and nonzero_pairs == 0),
        },
        "status": "normal_continuity_measured_runtime_not_approved",
        "next_gate": "validate collision parity on the same five 2 m cells, then streaming/render cost and deterministic visual fidelity",
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
    print("IXELLES_DTM_2M_NORMALS", json.dumps(result["aggregate"], sort_keys=True))
    return 0 if result["aggregate"]["normal_gate_pass"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
