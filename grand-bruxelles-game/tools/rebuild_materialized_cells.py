#!/usr/bin/env python3
"""Rebuild materialized UrbIS cells in place with the current pipeline.

Useful when the deterministic data pipeline changes (for example rail pruning or
runtime format fixes). Every existing built-cell manifest supplies the stable
cell ID and EPSG:31370 bbox, so no geometry is guessed and no zone grid needs to
be regenerated. The tool intentionally preserves the same cell directories.
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
BUILT_CELL_FORMAT = "grand-bruxelles-urbis-built-cell-v1"


def load_manifest(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("format") != BUILT_CELL_FORMAT:
        raise ValueError(f"unsupported cell manifest format in {path}")
    cell_id = str(payload.get("cell_id", "")).strip()
    bbox = payload.get("bbox")
    if not cell_id:
        raise ValueError(f"missing cell_id in {path}")
    if not isinstance(bbox, list) or len(bbox) != 4:
        raise ValueError(f"invalid bbox in {path}")
    return payload


def discover_cells(source_root: Path) -> list[dict[str, Any]]:
    cells: list[dict[str, Any]] = []
    for manifest_path in sorted(source_root.glob("*/manifest.json")):
        manifest = load_manifest(manifest_path)
        cells.append(
            {
                "cell_id": str(manifest["cell_id"]),
                "bbox": [float(value) for value in manifest["bbox"]],
                "output_dir": manifest_path.parent,
            }
        )
    ids = [cell["cell_id"] for cell in cells]
    if len(ids) != len(set(ids)):
        raise ValueError("duplicate materialized cell IDs discovered")
    return cells


def command_for_cell(cell: dict[str, Any], retries: int) -> list[str]:
    bbox_text = ",".join(str(value) for value in cell["bbox"])
    return [
        sys.executable,
        str(CELL_BUILDER),
        "--cell-id",
        str(cell["cell_id"]),
        "--bbox",
        bbox_text,
        "--output-dir",
        str(cell["output_dir"]),
        "--retries",
        str(max(1, retries)),
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description="Rebuild already materialized UrbIS cells in place")
    parser.add_argument(
        "--source-root",
        type=Path,
        default=ROOT / "data" / "urbis" / "remaining_brussels" / "cells",
    )
    parser.add_argument("--retries", type=int, default=4)
    parser.add_argument("--only", action="append", default=[], help="optional exact cell ID; repeatable")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    cells = discover_cells(args.source_root)
    if args.only:
        requested = set(args.only)
        known = {cell["cell_id"] for cell in cells}
        missing = sorted(requested - known)
        if missing:
            parser.error("unknown materialized cell(s): " + ", ".join(missing))
        cells = [cell for cell in cells if cell["cell_id"] in requested]

    for cell in cells:
        command = command_for_cell(cell, args.retries)
        print("REBUILD " + " ".join(command))
        if not args.dry_run:
            subprocess.run(command, check=True, cwd=ROOT)

    print(f"rebuilt/scheduled {len(cells)} materialized cell(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
