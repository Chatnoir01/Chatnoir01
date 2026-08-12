#!/usr/bin/env python3
"""Inspect paired DSM/DTM raster values before deriving Ixelles building heights."""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import numpy as np


def paired_stats(dsm: np.ndarray, dtm: np.ndarray, nodata_dsm: float | None, nodata_dtm: float | None) -> dict:
    if dsm.shape != dtm.shape:
        raise ValueError("DSM/DTM shapes differ")
    dsm = np.asarray(dsm, dtype=np.float64)
    dtm = np.asarray(dtm, dtype=np.float64)
    valid = np.isfinite(dsm) & np.isfinite(dtm)
    if nodata_dsm is not None and math.isfinite(float(nodata_dsm)):
        valid &= dsm != float(nodata_dsm)
    if nodata_dtm is not None and math.isfinite(float(nodata_dtm)):
        valid &= dtm != float(nodata_dtm)
    if not np.any(valid):
        raise ValueError("No paired valid DSM/DTM pixels")
    dsm_v = dsm[valid]
    dtm_v = dtm[valid]
    diff = dsm_v - dtm_v
    return {
        "paired_valid_count": int(diff.size),
        "dtm": {
            "min": round(float(np.min(dtm_v)), 4),
            "p05": round(float(np.percentile(dtm_v, 5)), 4),
            "p50": round(float(np.percentile(dtm_v, 50)), 4),
            "p95": round(float(np.percentile(dtm_v, 95)), 4),
            "max": round(float(np.max(dtm_v)), 4),
            "zero_fraction": round(float(np.count_nonzero(np.isclose(dtm_v, 0.0, atol=1e-6)) / dtm_v.size), 8),
        },
        "dsm": {
            "min": round(float(np.min(dsm_v)), 4),
            "p05": round(float(np.percentile(dsm_v, 5)), 4),
            "p50": round(float(np.percentile(dsm_v, 50)), 4),
            "p95": round(float(np.percentile(dsm_v, 95)), 4),
            "max": round(float(np.max(dsm_v)), 4),
            "zero_fraction": round(float(np.count_nonzero(np.isclose(dsm_v, 0.0, atol=1e-6)) / dsm_v.size), 8),
        },
        "dsm_minus_dtm": {
            "min": round(float(np.min(diff)), 4),
            "p05": round(float(np.percentile(diff, 5)), 4),
            "p50": round(float(np.percentile(diff, 50)), 4),
            "p95": round(float(np.percentile(diff, 95)), 4),
            "max": round(float(np.max(diff)), 4),
            "gt_0_5m_fraction": round(float(np.count_nonzero(diff > 0.5) / diff.size), 8),
            "near_zero_fraction": round(float(np.count_nonzero(np.isclose(diff, 0.0, atol=1e-4)) / diff.size), 8),
        },
    }


def find_single(root: Path, kind: str, tile: str) -> Path:
    matches = sorted((root / kind / tile).rglob("*.tif")) + sorted((root / kind / tile).rglob("*.tiff"))
    if len(matches) != 1:
        raise ValueError(f"Expected one {kind.upper()} TIFF for {tile}, found {matches}")
    return matches[0]


def inspect(root: Path, tiles: list[str]) -> dict:
    import rasterio
    result = {"schema": 1, "format": "grand-bruxelles-ixelles-height-value-diagnostics-v1", "tiles": []}
    for tile in tiles:
        dsm_path = find_single(root, "dsm", tile)
        dtm_path = find_single(root, "dtm", tile)
        with rasterio.open(dsm_path) as dsm_src, rasterio.open(dtm_path) as dtm_src:
            if dsm_src.shape != dtm_src.shape or tuple(dsm_src.transform) != tuple(dtm_src.transform):
                raise ValueError(f"{tile}: DSM/DTM grids differ")
            stats = paired_stats(dsm_src.read(1), dtm_src.read(1), dsm_src.nodata, dtm_src.nodata)
            result["tiles"].append({
                "tile": tile,
                "dsm_file": dsm_path.name,
                "dtm_file": dtm_path.name,
                "shape": list(dsm_src.shape),
                "transform": [float(v) for v in dsm_src.transform[:6]],
                "stats": stats,
            })
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--raster-root", type=Path, required=True)
    parser.add_argument("--tiles", nargs="+", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    payload = inspect(args.raster_root, args.tiles)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    for item in payload["tiles"]:
        print("IXELLES_HEIGHT_VALUE_DIAGNOSTIC", item["tile"], json.dumps(item["stats"], separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
