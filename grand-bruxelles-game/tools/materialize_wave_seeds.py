#!/usr/bin/env python3
"""Materialize a batch of globally unique wave seed cells.

Input is produced by select_wave_seed_cells.py. Cells are built sequentially to
avoid hammering the public UrbIS WFS and to keep failures attributable to one
stable 500 m Lambert72 cell. Existing completed cells are skipped unless
--force is supplied.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
CELL_BUILDER = ROOT / "tools" / "build_urbis_cell.py"
FORMAT = "grand-bruxelles-wave-seeds-v1"


def load_seed_batch(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("format") != FORMAT:
        raise ValueError(f"unsupported wave seed format: {path}")
    seeds = payload.get("seeds")
    if not isinstance(seeds, list) or not seeds:
        raise ValueError("wave seed batch must contain seeds")
    ids: list[str] = []
    for seed in seeds:
        if not isinstance(seed, dict):
            raise ValueError("invalid wave seed entry")
        cell_id = str(seed.get("cell_id", "")).strip()
        bbox = seed.get("bbox")
        if not cell_id.startswith("bxl-e"):
            raise ValueError(f"invalid global cell id: {cell_id!r}")
        if not isinstance(bbox, list) or len(bbox) != 4:
            raise ValueError(f"invalid bbox for {cell_id}")
        ids.append(cell_id)
    if len(ids) != len(set(ids)):
        raise ValueError("wave seed batch contains duplicate global cell IDs")
    if int(payload.get("seed_count", len(seeds))) != len(seeds):
        raise ValueError("wave seed_count does not match seeds length")
    return payload


def command_for_seed(seed: dict[str, Any], output_root: Path, retries: int) -> list[str]:
    bbox_text = ",".join(str(float(value)) for value in seed["bbox"])
    cell_id = str(seed["cell_id"])
    return [
        sys.executable,
        str(CELL_BUILDER),
        "--cell-id",
        cell_id,
        "--bbox",
        bbox_text,
        "--output-dir",
        str(output_root / cell_id),
        "--retries",
        str(max(1, retries)),
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description="Materialize one globally unique UrbIS cell per wave zone")
    parser.add_argument("--seeds", type=Path, required=True)
    parser.add_argument(
        "--output-root",
        type=Path,
        default=ROOT / "data" / "urbis" / "remaining_brussels" / "cells",
    )
    parser.add_argument("--retries", type=int, default=4)
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--limit", type=int, default=0, help="0 = all seeds")
    args = parser.parse_args()

    payload = load_seed_batch(args.seeds)
    seeds = list(payload["seeds"])
    if args.limit > 0:
        seeds = seeds[: args.limit]

    built = 0
    skipped = 0
    for seed in seeds:
        cell_id = str(seed["cell_id"])
        complete_marker = args.output_root / cell_id / "manifest.json"
        if complete_marker.exists() and not args.force:
            print(f"SKIP {seed['zone_id']} -> {cell_id} (already materialized)")
            skipped += 1
            continue
        command = command_for_seed(seed, args.output_root, args.retries)
        print(f"BUILD {seed['zone_id']} -> {cell_id}")
        print("  " + " ".join(command))
        if not args.dry_run:
            subprocess.run(command, check=True, cwd=ROOT)
        built += 1

    print(
        f"wave {payload.get('wave', '')}: built/scheduled={built}, skipped={skipped}, selected={len(seeds)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
