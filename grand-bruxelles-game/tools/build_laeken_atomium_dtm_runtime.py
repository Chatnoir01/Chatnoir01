#!/usr/bin/env python3
"""Build compact Godot-ready terrain data from an official UrbIS DTM XYZ grid.

Input XYZ must come from GDAL resampling of the official EPSG:31370 TIFF tile.
NoData cells are preserved as a validity mask instead of being interpreted as
terrain. Heights are stored relative to the nearest valid Atomium terrain sample
so the existing project-local Y=0 convention remains compatible.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

ORIGIN_E = 147868.29422791934
ORIGIN_N = 169538.62414926197
ATOMIUM_E = 148093.22038698208
ATOMIUM_N = 176091.76722726133
NO_DATA_THRESHOLD = -1.0e20


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("xyz", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--width", type=int, required=True)
    parser.add_argument("--height", type=int, required=True)
    parser.add_argument("--source-url", required=True)
    parser.add_argument("--source-sha256", required=True)
    return parser.parse_args()


def read_xyz(path: Path) -> list[tuple[float, float, float]]:
    points: list[tuple[float, float, float]] = []
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            fields = line.replace(",", " ").split()
            if len(fields) < 3:
                continue
            e, n, z = map(float, fields[:3])
            if not math.isfinite(z):
                raise ValueError(f"Non-finite elevation at {e}, {n}: {z}")
            points.append((e, n, z))
    return points


def is_valid_elevation(value: float) -> bool:
    return math.isfinite(value) and value > NO_DATA_THRESHOLD


def nearest_atomium(points: list[tuple[float, float, float]]) -> tuple[float, float, float]:
    valid = [point for point in points if is_valid_elevation(point[2])]
    if not valid:
        raise ValueError("DTM grid contains no valid elevation samples")
    return min(valid, key=lambda p: (p[0] - ATOMIUM_E) ** 2 + (p[1] - ATOMIUM_N) ** 2)


def main() -> int:
    args = parse_args()
    points = read_xyz(args.xyz)
    expected = args.width * args.height
    if len(points) != expected:
        raise SystemExit(f"Expected {expected} XYZ samples, got {len(points)}")

    atomium_sample = nearest_atomium(points)
    baseline = atomium_sample[2]
    valid_mask = [1 if is_valid_elevation(point[2]) else 0 for point in points]
    valid_elevations = [point[2] for point in points if is_valid_elevation(point[2])]
    relative: list[float] = []
    for point, valid in zip(points, valid_mask):
        relative.append(round(point[2] - baseline, 4) if valid else 0.0)
    valid_relative = [value for value, valid in zip(relative, valid_mask) if valid]

    eastings = [point[0] for point in points]
    northings = [point[1] for point in points]

    # GDAL XYZ is row-major, north-to-south for this GeoTIFF. Preserve exact
    # order and record spacing so Godot can reconstruct Lambert72 positions.
    first = points[0]
    second = points[1] if args.width > 1 else points[0]
    next_row = points[args.width] if args.height > 1 else points[0]
    step_e = second[0] - first[0]
    step_n = next_row[1] - first[1]

    output = {
        "schema": 2,
        "format": "grand-bruxelles-dtm-grid-v2",
        "source": "Paradigm UrbIS Digital Terrain Model 2021",
        "source_url": args.source_url,
        "source_sha256": args.source_sha256,
        "source_crs": "EPSG:31370",
        "width": args.width,
        "height": args.height,
        "first_sample_e": first[0],
        "first_sample_n": first[1],
        "step_e": step_e,
        "step_n": step_n,
        "game_origin_e": ORIGIN_E,
        "game_origin_n": ORIGIN_N,
        "atomium_reference": {
            "e": ATOMIUM_E,
            "n": ATOMIUM_N,
            "sample_e": atomium_sample[0],
            "sample_n": atomium_sample[1],
            "absolute_elevation_m": baseline,
        },
        "absolute_elevation_min_m": min(valid_elevations),
        "absolute_elevation_max_m": max(valid_elevations),
        "relative_height_min_m": min(valid_relative),
        "relative_height_max_m": max(valid_relative),
        "valid_sample_count": sum(valid_mask),
        "invalid_sample_count": len(valid_mask) - sum(valid_mask),
        "bounds_epsg31370": {
            "min_e": min(eastings),
            "max_e": max(eastings),
            "min_n": min(northings),
            "max_n": max(northings),
        },
        "relative_heights_m": relative,
        "valid_mask": valid_mask,
        "notes": "Valid heights are official DTM elevations minus the nearest valid Atomium sample. NoData cells are stored as mask=0 and must become holes, not terrain.",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, separators=(",", ":")) + "\n", encoding="utf-8")
    print(
        "LAEKEN_DTM_RUNTIME_OK",
        {
            "samples": len(relative),
            "valid": output["valid_sample_count"],
            "invalid": output["invalid_sample_count"],
            "baseline": baseline,
            "absolute_range": [min(valid_elevations), max(valid_elevations)],
            "relative_range": [min(valid_relative), max(valid_relative)],
            "step": [step_e, step_n],
        },
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
