#!/usr/bin/env python3
"""Sample one C01 DTM tile by the GeoTIFF's actual metric bounds.

Boundary ownership must follow raster bounds, not nominal kilometre labels: UrbIS DTM
GeoTIFF origins are sub-metre offset from the integer-kilometre tile code.
"""
from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path

import audit_region_lod2_c01_dtm_rigid_anchor as core


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--tile", required=True)
    ap.add_argument("--samples", type=Path, required=True)
    ap.add_argument("--sources", type=Path, required=True)
    ap.add_argument("--contract", type=Path, required=True)
    ap.add_argument("--output-dir", type=Path, required=True)
    ap.add_argument("--work-dir", type=Path, required=True)
    args = ap.parse_args()
    try:
        contract = json.loads(args.contract.read_text(encoding="utf-8"))
        core.validate_hard_rules(contract)
        sources = json.loads(args.sources.read_text(encoding="utf-8"))
        source_map = {str(row["tile"]): str(row["url"]) for row in sources["tiles"]}
        if args.tile not in source_map:
            raise RuntimeError(f"tile {args.tile} absent from resolved DTM sources")

        args.work_dir.mkdir(parents=True, exist_ok=True)
        archive = args.work_dir / f"dtm-{args.tile}.zip"
        core.bounded_curl(source_map[args.tile], archive, retries=4, max_seconds=240)
        archive_sha = core.sha256_file(archive)
        members = core.safe_extract_zip(archive, args.work_dir / f"dtm-{args.tile}")
        tiffs = sorted(p for p in members if p.suffix.lower() in {".tif", ".tiff"})
        if len(tiffs) != 1:
            raise RuntimeError(f"{args.tile}: expected one TIFF, got {[p.name for p in tiffs]}")
        tif = tiffs[0]
        src, meta = core.validate_raster(args.tile, tif, float(contract["dtm"]["expected_resolution_m"]))
        bounds = src.bounds

        selected: list[dict[str, str]] = []
        with args.samples.open(newline="", encoding="utf-8") as f:
            for row in csv.DictReader(f):
                e = float(row["easting"])
                n = float(row["northing"])
                if float(bounds.left) <= e < float(bounds.right) and float(bounds.bottom) < n <= float(bounds.top):
                    selected.append(row)
        if not selected:
            src.close()
            raise RuntimeError(f"{args.tile}: actual raster bounds contain no C01 ground samples")

        args.output_dir.mkdir(parents=True, exist_ok=True)
        residual_path = args.output_dir / f"residuals_{args.tile}.csv"
        vals: list[float] = []
        with residual_path.open("w", newline="", encoding="utf-8") as f:
            fields = ["tile", "building_id", "easting", "northing", "source_ground_z", "dtm_z", "residual_source_minus_dtm_m"]
            writer = csv.DictWriter(f, fieldnames=fields)
            writer.writeheader()
            for row in selected:
                e = float(row["easting"])
                n = float(row["northing"])
                source_z = float(row["source_ground_z"])
                value = next(src.sample([(e, n)], masked=True))[0]
                if hasattr(value, "mask") and bool(value.mask):
                    src.close()
                    raise RuntimeError(f"{args.tile}: nodata at {e},{n}")
                dtm_z = float(value)
                if not math.isfinite(dtm_z) or (src.nodata is not None and dtm_z == float(src.nodata)):
                    src.close()
                    raise RuntimeError(f"{args.tile}: invalid DTM value {dtm_z} at {e},{n}")
                residual = source_z - dtm_z
                vals.append(residual)
                writer.writerow({
                    "tile": args.tile,
                    "building_id": row["building_id"],
                    "easting": row["easting"],
                    "northing": row["northing"],
                    "source_ground_z": row["source_ground_z"],
                    "dtm_z": f"{dtm_z:.9f}",
                    "residual_source_minus_dtm_m": f"{residual:.9f}",
                })
        src.close()
        evidence = {
            "schema": "grand-bruxelles-region-lod2-c01-dtm-tile-evidence-v2",
            "tile": args.tile,
            "assignment_basis": "actual_geotiff_metric_bounds",
            "url": source_map[args.tile],
            "archive_sha256": archive_sha,
            "archive_bytes": archive.stat().st_size,
            "raster_filename": tif.name,
            "raster_sha256": core.sha256_file(tif),
            "samples": len(vals),
            "source_minus_dtm_min_m": min(vals),
            "source_minus_dtm_max_m": max(vals),
            "raster": meta,
            "runtime_authorized": False,
            "final_world_y_authorized": False
        }
        (args.output_dir / f"dtm_evidence_{args.tile}.json").write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
        print(f"C01_DTM_TILE_BOUNDS_OK: tile={args.tile} samples={len(vals)} archive_sha256={archive_sha}")
        return 0
    except Exception as exc:
        print(f"C01_DTM_TILE_BOUNDS_ERROR: {exc}", flush=True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
