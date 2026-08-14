#!/usr/bin/env python3
"""Materialize the already-validated 2 m DTM for the first Ixelles runtime micro-slice.

This is a runtime packaging step, not a new terrain study. Sampling is delegated to
the merged measured-seams implementation so the runtime payload cannot silently
drift from the seam/normal evidence. The resulting file remains non-approved until
Godot render/collision transform parity and a deterministic capture pass.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path

import numpy as np

SELECTED_CELL_ID = "bxl-e149000-n169000-s500"
SELECTED_BBOX = (149000.0, 169000.0, 149500.0, 169500.0)
EXPECTED_ARCHIVES = {
    "149168": "f0277df26876c6c7cd3e00050e3d3a44b420b2df4bf4271e680717adeabb09b4",
    "149169": "c8135aa8456a5f2de8efb2e05dbf9c993ae9c97e4aa7f4d56c6c331345bac4f8",
}


def _load_sampler():
    path = Path(__file__).with_name("measure_ixelles_dtm_2m_seams.py")
    spec = importlib.util.spec_from_file_location("ixelles_measured_seams", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load merged DTM sampler: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def hash_grid(grid: np.ndarray) -> str:
    normalized = np.ascontiguousarray(grid.astype("<f8", copy=False))
    return hashlib.sha256(normalized.tobytes()).hexdigest()


def build_payload(cell_id: str, grid: np.ndarray, metadata: dict) -> dict:
    if cell_id != SELECTED_CELL_ID:
        raise ValueError(f"Only the selected Ixelles micro-slice is allowed: {SELECTED_CELL_ID}")
    if grid.shape != (251, 251):
        raise ValueError(f"Expected 251x251 2 m grid, got {grid.shape}")
    if not np.isfinite(grid).all():
        raise ValueError("Runtime DTM contains non-finite samples")
    supplied_hash = metadata.get("grid_sha256")
    actual_hash = hash_grid(grid)
    if supplied_hash and supplied_hash != actual_hash:
        raise ValueError("Grid hash does not match sampled terrain")
    archives = metadata.get("archive_sha256", {})
    for tile, expected in EXPECTED_ARCHIVES.items():
        if archives and archives.get(tile) != expected:
            raise ValueError(f"Archive hash contract drift for {tile}")

    values = [round(float(v), 6) for v in grid.reshape(-1)]
    return {
        "schema": "grand-bruxelles-ixelles-runtime-dtm-v1",
        "cell_id": SELECTED_CELL_ID,
        "bbox_epsg31370": list(SELECTED_BBOX),
        "spacing_m": 2.0,
        "shape": [251, 251],
        "sample_count": 63001,
        "source": {
            "publisher": "Paradigm / Brussels-Capital Region",
            "dataset": "UrbIS Digital Terrain Model 2021",
            "crs": "EPSG:31370",
            "source_resolution_m": 0.5,
            "archive_sha256": EXPECTED_ARCHIVES,
            "sampler": "measure_ixelles_dtm_2m_seams.py",
        },
        "grid_float64_sha256": actual_hash,
        "min_z_m": round(float(np.min(grid)), 6),
        "max_z_m": round(float(np.max(grid)), 6),
        "heights_row_major_m": values,
        "runtime_approved": False,
        "promote_runtime": False,
        "approval_blockers": [
            "Godot render/collision transform parity",
            "deterministic player-visible capture and human review",
        ],
    }


def write_payload(payload: dict, output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n")


def materialize(rasters: list[Path], output: Path, archive_hashes: dict[str, str]) -> dict:
    if archive_hashes != EXPECTED_ARCHIVES:
        raise ValueError("Locked UrbIS DTM archive hashes are required")
    sampler = _load_sampler()
    array, transform, _crs_origins = sampler.open_mosaic(rasters)
    grid = sampler.make_grid(array, transform, SELECTED_BBOX)
    metadata = {"archive_sha256": archive_hashes, "grid_sha256": hash_grid(grid)}
    payload = build_payload(SELECTED_CELL_ID, grid, metadata)
    write_payload(payload, output)
    return payload


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--raster", nargs=2, required=True, type=Path)
    parser.add_argument("--archive-hash", action="append", default=[])
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    archive_hashes = dict(item.split("=", 1) for item in args.archive_hash)
    payload = materialize(args.raster, args.output, archive_hashes)
    print(json.dumps({
        "cell_id": payload["cell_id"],
        "sample_count": payload["sample_count"],
        "grid_float64_sha256": payload["grid_float64_sha256"],
        "min_z_m": payload["min_z_m"],
        "max_z_m": payload["max_z_m"],
        "runtime_approved": payload["runtime_approved"],
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
