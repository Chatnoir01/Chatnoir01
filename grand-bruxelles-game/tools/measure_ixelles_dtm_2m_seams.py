#!/usr/bin/env python3
"""Generate the five validated Ixelles 2 m DTM grids and measure shared seams.

Evidence only. The authoritative input is UrbIS DTM 2021 in EPSG:31370.
Every cell is sampled independently from the same global 2 m lattice and the same
float64/NaN-safe raster mosaic. No runtime terrain is approved by this tool.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path

import numpy as np

EXPECTED_CRS = "EPSG:31370"
SOURCE_PIXEL_M = 0.5
SPACING_M = 2.0
CELLS = [
    ("bxl-e149000-n169000-s500", (149000.0, 169000.0, 149500.0, 169500.0)),
    ("bxl-e149000-n169500-s500", (149000.0, 169500.0, 149500.0, 170000.0)),
    ("bxl-e149500-n168500-s500", (149500.0, 168500.0, 150000.0, 169000.0)),
    ("bxl-e149500-n169000-s500", (149500.0, 169000.0, 150000.0, 169500.0)),
    ("bxl-e149500-n169500-s500", (149500.0, 169500.0, 150000.0, 170000.0)),
]
SHARED_EDGES = [
    ("bxl-e149000-n169000-s500", "north", "bxl-e149000-n169500-s500", "south"),
    ("bxl-e149500-n168500-s500", "north", "bxl-e149500-n169000-s500", "south"),
    ("bxl-e149500-n169000-s500", "north", "bxl-e149500-n169500-s500", "south"),
    ("bxl-e149000-n169000-s500", "east", "bxl-e149500-n169000-s500", "west"),
    ("bxl-e149000-n169500-s500", "east", "bxl-e149500-n169500-s500", "west"),
]
SOURCE_ARCHIVES = {
    "149168": "f0277df26876c6c7cd3e00050e3d3a44b420b2df4bf4271e680717adeabb09b4",
    "149169": "c8135aa8456a5f2de8efb2e05dbf9c993ae9c97e4aa7f4d56c6c331345bac4f8",
}


def bilinear_sample(array: np.ndarray, transform, xs: np.ndarray, ys: np.ndarray) -> np.ndarray:
    """NaN-aware bilinear sample with a strict half-pixel outer support strip.

    The locked UrbIS TIFFs are 0.5 m rasters whose affine origin is offset by a
    small sub-pixel amount from the exact 1 km Lambert72 archive grid. Runtime
    vertices nevertheless live on the exact EPSG:31370 2 m lattice. Samples up to
    half a source pixel outside the affine raster edge are therefore clamped to the
    nearest official pixel; points farther out remain NaN. Interior samples keep
    ordinary bilinear interpolation unchanged.
    """
    if transform.b != 0 or transform.d != 0 or transform.a <= 0 or transform.e >= 0:
        raise ValueError("Expected north-up source raster")

    raw_cols = (xs - transform.c) / transform.a - 0.5
    raw_rows = (ys - transform.f) / transform.e - 0.5
    height, width = array.shape

    # raw pixel-centre coordinates are -0.5 at the affine outer edge. Extend by
    # exactly another half pixel (-1.0 / dimension) to tolerate only the official
    # sub-pixel transform offset; never pull values from farther outside.
    supported = (
        (raw_cols >= -1.0)
        & (raw_cols <= width)
        & (raw_rows >= -1.0)
        & (raw_rows <= height)
    )
    out = np.full(xs.shape, np.nan, dtype=np.float64)
    if not np.any(supported):
        return out

    idx = np.where(supported)[0]
    cols = np.clip(raw_cols[idx], 0.0, width - 1.0)
    rows = np.clip(raw_rows[idx], 0.0, height - 1.0)
    c0 = np.floor(cols).astype(np.int64)
    r0 = np.floor(rows).astype(np.int64)
    c1 = np.minimum(c0 + 1, width - 1)
    r1 = np.minimum(r0 + 1, height - 1)
    dc = cols - c0
    dr = rows - r0

    vals = np.stack(
        [array[r0, c0], array[r0, c1], array[r1, c0], array[r1, c1]],
        axis=1,
    )
    weights = np.stack(
        [
            (1 - dr) * (1 - dc),
            (1 - dr) * dc,
            dr * (1 - dc),
            dr * dc,
        ],
        axis=1,
    )
    finite = np.isfinite(vals)
    denom = np.where(finite, weights, 0.0).sum(axis=1)
    good = denom > 0
    sampled = np.full(idx.shape, np.nan, dtype=np.float64)
    sampled[good] = np.where(finite, vals * weights, 0.0)[good].sum(axis=1) / denom[good]
    out[idx] = sampled
    return out


def open_locked_source(path: Path):
    """Open a locked UrbIS DTM raster with explicit CRS handling.

    The official 2021 TIFF payloads currently ship with a valid Lambert72 affine
    transform but no embedded CRS tag. Because the archive URLs and SHA-256 values
    are locked by this evidence lot, a missing CRS is treated as missing metadata,
    not as permission to reinterpret pixels. We create an in-memory copy with only
    EPSG:31370 attached; pixels, dtype, nodata and transform are preserved exactly.
    Any *present* non-31370 CRS is rejected.

    Returns (dataset, owner, crs_origin). ``owner`` must stay alive for an in-memory
    dataset and is None for a source that already embeds the expected CRS.
    """
    import rasterio
    from rasterio.io import MemoryFile

    src = rasterio.open(path)
    if src.crs is not None:
        if str(src.crs) != EXPECTED_CRS:
            actual = src.crs
            src.close()
            raise ValueError(f"Unexpected CRS {actual} for {path}")
        return src, None, "embedded"

    profile = src.profile.copy()
    profile.update(crs=EXPECTED_CRS)
    owner = MemoryFile()
    locked = owner.open(**profile)
    try:
        for band in range(1, src.count + 1):
            locked.write(src.read(band), band)
        if src.dataset_mask().size:
            locked.write_mask(src.dataset_mask())
        locked.update_tags(**src.tags())
    except Exception:
        locked.close()
        owner.close()
        src.close()
        raise
    src.close()
    return locked, owner, "assumed_from_locked_urbis_dtm_contract"


def open_mosaic(paths: list[Path]):
    from rasterio.merge import merge

    datasets = []
    owners = []
    crs_origins = []
    try:
        for path in paths:
            ds, owner, crs_origin = open_locked_source(path)
            datasets.append(ds)
            if owner is not None:
                owners.append(owner)
            crs_origins.append(crs_origin)
            if not (
                math.isclose(abs(ds.transform.a), SOURCE_PIXEL_M)
                and math.isclose(abs(ds.transform.e), SOURCE_PIXEL_M)
            ):
                raise ValueError(f"Unexpected source pixel size for {ds.name}: {ds.transform}")

        mosaic, transform = merge(datasets, dtype="float64", nodata=np.nan, masked=False)
        array = mosaic[0].astype(np.float64, copy=False)
        for ds in datasets:
            if ds.nodata is not None and np.isfinite(ds.nodata):
                array[array == float(ds.nodata)] = np.nan
        return array, transform, crs_origins
    finally:
        for ds in datasets:
            ds.close()
        for owner in owners:
            owner.close()


def make_grid(array: np.ndarray, transform, bbox: tuple[float, float, float, float]) -> np.ndarray:
    west, south, east, north = bbox
    xs = np.arange(west, east + SPACING_M * 0.5, SPACING_M, dtype=np.float64)
    ys = np.arange(south, north + SPACING_M * 0.5, SPACING_M, dtype=np.float64)
    if xs.size != 251 or ys.size != 251:
        raise AssertionError(f"Expected 251x251 lattice, got {xs.size}x{ys.size}")
    yy, xx = np.meshgrid(ys, xs, indexing="ij")
    return bilinear_sample(array, transform, xx.reshape(-1), yy.reshape(-1)).reshape(251, 251)


def edge(grid: np.ndarray, side: str) -> np.ndarray:
    if side == "north":
        return grid[-1, :]
    if side == "south":
        return grid[0, :]
    if side == "east":
        return grid[:, -1]
    if side == "west":
        return grid[:, 0]
    raise ValueError(side)


def hash_grid(grid: np.ndarray) -> str:
    normalized = np.ascontiguousarray(grid.astype("<f8", copy=False))
    return hashlib.sha256(normalized.tobytes()).hexdigest()


def measure(paths: list[Path], archive_hashes: dict[str, str]) -> dict:
    array, transform, crs_origins = open_mosaic(paths)
    finite = array[np.isfinite(array)]
    if finite.size == 0 or float(np.max(finite) - np.min(finite)) < 0.25:
        raise ValueError("Official DTM mosaic is degenerate")

    grids: dict[str, np.ndarray] = {}
    cells_out = []
    for cell_id, bbox in CELLS:
        grid = make_grid(array, transform, bbox)
        grids[cell_id] = grid
        finite_grid = grid[np.isfinite(grid)]
        if finite_grid.size != grid.size:
            raise ValueError(f"Non-finite 2 m samples in {cell_id}: {grid.size - finite_grid.size}")
        cells_out.append(
            {
                "cell_id": cell_id,
                "bbox_epsg31370": list(bbox),
                "shape": [251, 251],
                "samples": int(grid.size),
                "min_z_m": round(float(np.min(finite_grid)), 6),
                "max_z_m": round(float(np.max(finite_grid)), 6),
                "mean_z_m": round(float(np.mean(finite_grid)), 6),
                "float64_grid_sha256": hash_grid(grid),
            }
        )

    seams = []
    all_deltas = []
    for a_id, a_side, b_id, b_side in SHARED_EDGES:
        av = edge(grids[a_id], a_side)
        bv = edge(grids[b_id], b_side)
        finite = np.isfinite(av) & np.isfinite(bv)
        if int(np.count_nonzero(finite)) != 251:
            raise ValueError(f"Incomplete shared edge {a_id}/{b_id}")
        delta = np.abs(av[finite] - bv[finite])
        all_deltas.append(delta)
        seams.append(
            {
                "a": a_id,
                "a_side": a_side,
                "b": b_id,
                "b_side": b_side,
                "paired_samples": 251,
                "max_abs_delta_m": float(np.max(delta)),
                "mean_abs_delta_m": float(np.mean(delta)),
                "nonzero_delta_count": int(np.count_nonzero(delta)),
                "a_edge_sha256": hash_grid(av),
                "b_edge_sha256": hash_grid(bv),
            }
        )
    joined = np.concatenate(all_deltas)
    max_delta = float(np.max(joined))
    nonzero = int(np.count_nonzero(joined))
    return {
        "schema": "grand-bruxelles-ixelles-dtm-2m-measured-seams-v1",
        "source_crs": EXPECTED_CRS,
        "source_crs_origin": crs_origins,
        "dataset": "Paradigm / Brussels-Capital Region UrbIS Digital Terrain Model 2021",
        "source_pixel_size_m": SOURCE_PIXEL_M,
        "candidate_resolution_m": SPACING_M,
        "source_archive_sha256": archive_hashes,
        "sampling_method": "NaN-safe bilinear sample of one float64 official-raster mosaic at a global EPSG:31370 2 m lattice; inclusive 500 m cell boundaries",
        "outer_mosaic_boundary_policy": "one-sided nearest-official-pixel clamp limited to at most half a 0.5 m source pixel beyond the affine raster edge, solely to absorb the locked UrbIS TIFF sub-pixel transform offset; no farther extrapolation",
        "crs_policy": "embedded EPSG:31370 accepted; missing TIFF CRS may be attached only for the two locked official UrbIS DTM archives without changing pixels or affine transform; any conflicting embedded CRS is rejected",
        "runtime_approved": False,
        "promote_runtime": False,
        "cells": cells_out,
        "shared_edges": seams,
        "aggregate": {
            "cell_count": 5,
            "grid_samples_per_cell": 63001,
            "grid_samples_total_before_cross_cell_dedup": 315005,
            "shared_edge_count": 5,
            "shared_edge_pairs": int(joined.size),
            "max_abs_shared_edge_delta_m": max_delta,
            "nonzero_shared_edge_delta_count": nonzero,
            "seam_gate_pass": bool(max_delta == 0.0 and nonzero == 0),
        },
        "status": "seams_measured_runtime_not_approved",
        "next_gate": "validate normals from central differences across shared borders, then collision parity, streaming/render cost and deterministic visual fidelity",
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
    print("IXELLES_DTM_2M_SEAMS", json.dumps(agg, sort_keys=True))
    if not agg["seam_gate_pass"]:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
