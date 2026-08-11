#!/usr/bin/env python3
"""Materialize every cell from a make_zone_cells.py manifest.

Each cell is fetched independently, so a failed network request can be retried
without rebuilding the whole municipality. Existing completed cells can be
skipped unless --force is requested.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CELL_BUILDER = ROOT / "tools" / "build_urbis_cell.py"


def load_manifest(path: Path) -> dict:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("format") != "grand-bruxelles-zone-cells-v1":
        raise ValueError("unsupported cell manifest format")
    if not isinstance(payload.get("cells"), list):
        raise ValueError("cell manifest has no cells list")
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
    parser.add_argument("--output-root", type=Path, required=True)
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
            print(f"SKIP {cell['id']} (already materialized)")
            skipped += 1
            continue
        command = command_for_cell(cell, args.output_root, max(1, args.retries))
        print("RUN  " + " ".join(command))
        if not args.dry_run:
            subprocess.run(command, check=True, cwd=ROOT)
        completed += 1

    print(f"zone {manifest['zone_id']}: scheduled/built={completed}, skipped={skipped}, total={len(cells)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
