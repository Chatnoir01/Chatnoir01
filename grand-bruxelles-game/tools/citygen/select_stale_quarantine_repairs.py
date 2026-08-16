#!/usr/bin/env python3
"""Select stale CityGen quarantine candidates whose authoritative source cache vanished.

This is deliberately narrow: only a previously generated QUARANTINE candidate with
`invalid_building_features_present` is eligible, and only when no durable source
directory exists. The selector never reconstructs geometry itself; it emits the
canonical target-grid bbox so the existing UrbIS WFS materializer can rebuild the
cell from authority.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

TARGET_FORMAT = "grand-bruxelles-regional-target-grid-v1"
REPAIR_BLOCKER = "invalid_building_features_present"


def read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def target_bboxes(path: Path) -> dict[str, list[int | float]]:
    payload = read_json(path)
    if payload.get("format") != TARGET_FORMAT or payload.get("crs") != "EPSG:31370":
        raise ValueError("unsupported regional target grid or CRS")
    out: dict[str, list[int | float]] = {}
    for row in payload.get("cells") or []:
        if not isinstance(row, dict):
            raise ValueError("target grid cells must be objects")
        cell_id = row.get("cell_id")
        bbox = row.get("bbox")
        if not isinstance(cell_id, str) or not cell_id.startswith("bxl-") or cell_id in out:
            raise ValueError("target grid contains invalid or duplicate cell id")
        if not isinstance(bbox, list) or len(bbox) != 4 or not all(isinstance(v, (int, float)) for v in bbox):
            raise ValueError(f"target grid cell has invalid bbox: {cell_id}")
        if not (bbox[0] < bbox[2] and bbox[1] < bbox[3]):
            raise ValueError(f"target grid cell has non-positive bbox: {cell_id}")
        out[cell_id] = bbox
    return out


def select_repairs(candidate_root: Path, source_root: Path, target_grid: Path, limit: int) -> list[dict[str, Any]]:
    if limit < 1 or limit > 32:
        raise ValueError("limit must be between 1 and 32")
    bboxes = target_bboxes(target_grid)
    repairs: list[dict[str, Any]] = []
    if not candidate_root.exists():
        return repairs
    for path in sorted(candidate_root.glob("bxl-*.json")):
        candidate = read_json(path)
        cell_id = candidate.get("cell_id") or path.stem
        if cell_id != path.stem or cell_id not in bboxes:
            continue
        if candidate.get("status") != "QUARANTINE":
            continue
        blockers = candidate.get("blockers") or []
        if not isinstance(blockers, list) or REPAIR_BLOCKER not in blockers:
            continue
        if (source_root / cell_id).exists():
            continue
        repairs.append({"cell_id": cell_id, "bbox": bboxes[cell_id], "candidate_path": str(path)})
        if len(repairs) >= limit:
            break
    return repairs


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate-root", type=Path, required=True)
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--target-grid", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--limit", type=int, default=4)
    args = parser.parse_args()
    repairs = select_repairs(args.candidate_root, args.source_root, args.target_grid, args.limit)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        "".join(row["cell_id"] + "\t" + ",".join(str(v) for v in row["bbox"]) + "\n" for row in repairs),
        encoding="utf-8",
    )
    print(f"STALE_QUARANTINE_REPAIRS_OK selected={len(repairs)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
