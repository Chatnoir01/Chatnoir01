#!/usr/bin/env python3
"""Sample a committed Laeken/Jette DTM runtime at an EPSG:31370 point.

The runtime stores official UrbIS DTM elevations relative to the nearest valid
Atomium terrain sample. This tool reconstructs an absolute elevation only from
that pinned baseline plus valid grid samples. It never extrapolates outside the
runtime bounds and never treats NoData as zero terrain.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("runtime", type=Path)
    parser.add_argument("--e", type=float, required=True)
    parser.add_argument("--n", type=float, required=True)
    parser.add_argument("--eye-height", type=float, default=1.70)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def valid_at(data: dict, row: int, col: int) -> bool:
    if row < 0 or col < 0 or row >= data["height"] or col >= data["width"]:
        return False
    idx = row * data["width"] + col
    return bool(data["valid_mask"][idx])


def relative_at(data: dict, row: int, col: int) -> float:
    idx = row * data["width"] + col
    return float(data["relative_heights_m"][idx])


def main() -> int:
    args = parse_args()
    data = json.loads(args.runtime.read_text(encoding="utf-8"))
    if data.get("source_crs") != "EPSG:31370":
        raise SystemExit(f"Unexpected CRS: {data.get('source_crs')}")
    if data.get("format") != "grand-bruxelles-dtm-grid-v2":
        raise SystemExit(f"Unexpected runtime format: {data.get('format')}")

    bounds = data["bounds_epsg31370"]
    if not (bounds["min_e"] <= args.e <= bounds["max_e"] and bounds["min_n"] <= args.n <= bounds["max_n"]):
        raise SystemExit(f"Point outside DTM runtime bounds: E{args.e} N{args.n} vs {bounds}")

    step_e = float(data["step_e"])
    step_n = float(data["step_n"])
    if step_e == 0 or step_n == 0:
        raise SystemExit("Invalid zero DTM spacing")

    col_f = (args.e - float(data["first_sample_e"])) / step_e
    row_f = (args.n - float(data["first_sample_n"])) / step_n
    col0 = math.floor(col_f)
    row0 = math.floor(row_f)
    tx = col_f - col0
    ty = row_f - row0

    corners = [
        (row0, col0, (1.0 - tx) * (1.0 - ty)),
        (row0, col0 + 1, tx * (1.0 - ty)),
        (row0 + 1, col0, (1.0 - tx) * ty),
        (row0 + 1, col0 + 1, tx * ty),
    ]
    usable = [(r, c, w) for r, c, w in corners if valid_at(data, r, c) and w > 0]
    if len(usable) != 4:
        raise SystemExit(f"Cannot bilinearly sample point because one or more DTM corners are NoData: {corners}")

    relative = sum(relative_at(data, r, c) * w for r, c, w in usable)
    baseline = float(data["atomium_reference"]["absolute_elevation_m"])
    absolute = baseline + relative
    if not (0.0 < absolute < 120.0):
        raise SystemExit(f"Implausible Brussels DTM elevation: {absolute}")

    nearest_col = int(round(col_f))
    nearest_row = int(round(row_f))
    nearest_valid = valid_at(data, nearest_row, nearest_col)
    nearest_relative = relative_at(data, nearest_row, nearest_col) if nearest_valid else None

    result = {
        "schema": 1,
        "source_runtime": str(args.runtime),
        "source_crs": "EPSG:31370",
        "source_sha256": data.get("source_sha256"),
        "query_epsg31370": {"e": args.e, "n": args.n},
        "runtime_bounds_epsg31370": bounds,
        "grid_fractional": {"row": row_f, "col": col_f},
        "bilinear_corners": [
            {"row": r, "col": c, "weight": w, "relative_height_m": relative_at(data, r, c)}
            for r, c, w in usable
        ],
        "atomium_baseline_absolute_elevation_m": baseline,
        "terrain_relative_to_atomium_m": relative,
        "terrain_absolute_elevation_m": absolute,
        "eye_height_m": args.eye_height,
        "camera_eye_absolute_elevation_m": absolute + args.eye_height,
        "nearest_sample": {
            "row": nearest_row,
            "col": nearest_col,
            "valid": nearest_valid,
            "relative_height_m": nearest_relative,
        },
        "method": "Bilinear interpolation of four valid committed 5 m UrbIS DTM runtime samples; absolute elevation reconstructed from the runtime's pinned Atomium absolute baseline. No extrapolation and no NoData substitution.",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("LAEKEN_DTM_SAMPLE_OK", round(absolute, 4), round(absolute + args.eye_height, 4))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
