#!/usr/bin/env python3
"""Materialize every globally identified cell from a zone manifest.

Zone manifests v2 contain only cells that intersect the official boundary and
use a global Lambert72-derived cell ID. Processing adjacent municipalities into
the same output root therefore reuses/skips shared squares instead of duplicating
them under different municipality-specific names.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CELL_BUILDER = ROOT / "tools" / "build_urbis_cell.py"
CELL_FORMAT = "grand-bruxelles-zone-cells-v2"


def load_manifest(path: Path) -> dict:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("format") != CELL_FORMAT:
        raise ValueError(
            f"unsupported cell manifest format: expected {CELL_FORMAT}; regenerate old envelope-only manifests"
        )
    if not isinstance(payload.get("cells"), list):
        raise ValueError("cell manifest has no cells list")
    ids = [str(cell.get("id", "")) for cell in payload["cells"] if isinstance(cell, dict)]
    if not ids or any(not cell_id.startswith("bxl-e") for cell_id in ids):
        raise ValueError("cell manifest does not use global Lambert72 cell IDs")
    if len(ids) != len(set(ids)):
        raise ValueError("cell manifest contains duplicate cell IDs")
    return payload


def command_for_cell(cell: dict, output_root: Path, retries: int) -> list[str]:
    bbox = cell["bbox"]
    bbox_text = ",".join(str(value) for value in bbox)
    return [
        sys.executable,
        str(CELL_BUILDER),
        "--cell-id",
        str(cell["id"]),
        "--bbox",
        bbox_text,
        "--output-dir",
        str(output_root / str(cell["id"])),
        "--retries",
        str(retries),
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description="Build all official UrbIS runtime cells for one zone")
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument(
        "--output-root",
        type=Path,
        default=ROOT / "data" / "urbis" / "remaining_brussels" / "cells",
    )
    parser.add_argument("--retries", type=int, default=4)
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--limit", type=int, default=0, help="0 = no limit")
    args = parser.parse_args()

    manifest = load_manifest(args.manifest)
    cells = manifest["cells"]
    if args.limit > 0:
        cells = cells[: args.limit]

    completed = 0
    skipped = 0
    for cell in cells:
        cell_dir = args.output_root / str(cell["id"])
        complete_marker = cell_dir / "manifest.json"
        if complete_marker.exists() and not args.force:
            print(f"SKIP {cell['id']} (global cell already materialized)")
            skipped += 1
            continue
        command = command_for_cell(cell, args.output_root, max(1, args.retries))
        print("RUN  " + " ".join(command))
        if not args.dry_run:
            subprocess.run(command, check=True, cwd=ROOT)
        completed += 1

    print(
        f"zone {manifest['zone_id']}: scheduled/built={completed}, skipped={skipped}, total={len(cells)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
