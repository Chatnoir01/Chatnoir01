#!/usr/bin/env python3
"""Select the best seed cell from an official zone-cell manifest.

The default strategy chooses the cell whose rectangle is closest to a Lambert72
anchor.  This avoids materializing arbitrary edge cells simply because their
global IDs sort first.  For R1 Anderlecht we anchor on the project's official
Bruxelles-Midi Lambert72 control point so expansion starts at the existing world
seam toward Cureghem.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

FORMAT = "grand-bruxelles-zone-cells-v2"


def load_manifest(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("format") != FORMAT:
        raise ValueError(f"unsupported manifest format: expected {FORMAT}")
    cells = payload.get("cells")
    if not isinstance(cells, list) or not cells:
        raise ValueError("manifest must contain cells")
    return payload


def distance_point_to_bbox(e: float, n: float, bbox: list[float]) -> float:
    if len(bbox) != 4:
        raise ValueError("bbox must contain four coordinates")
    min_e, min_n, max_e, max_n = [float(value) for value in bbox]
    if min_e >= max_e or min_n >= max_n:
        raise ValueError("invalid bbox extent")
    nearest_e = min(max(e, min_e), max_e)
    nearest_n = min(max(n, min_n), max_n)
    return math.hypot(e - nearest_e, n - nearest_n)


def select_seed(payload: dict[str, Any], anchor_e: float, anchor_n: float) -> dict[str, Any]:
    ranked = []
    for cell in payload["cells"]:
        if not isinstance(cell, dict) or "bbox" not in cell or "id" not in cell:
            continue
        distance = distance_point_to_bbox(anchor_e, anchor_n, cell["bbox"])
        center_e = (float(cell["bbox"][0]) + float(cell["bbox"][2])) * 0.5
        center_n = (float(cell["bbox"][1]) + float(cell["bbox"][3])) * 0.5
        center_distance = math.hypot(anchor_e - center_e, anchor_n - center_n)
        ranked.append((distance, center_distance, str(cell["id"]), cell))
    if not ranked:
        raise ValueError("manifest contains no selectable cells")
    ranked.sort(key=lambda item: (item[0], item[1], item[2]))
    distance, _, _, selected = ranked[0]
    return {**selected, "seed_distance_m": round(distance, 3)}


def one_cell_manifest(payload: dict[str, Any], selected: dict[str, Any], anchor_e: float, anchor_n: float) -> dict[str, Any]:
    result = dict(payload)
    result["cells"] = [{key: value for key, value in selected.items() if key != "seed_distance_m"}]
    result["cell_count"] = 1
    result["seed_selection"] = {
        "strategy": "nearest_bbox_to_lambert72_anchor",
        "anchor": [anchor_e, anchor_n],
        "selected_cell_id": selected["id"],
        "distance_m": selected["seed_distance_m"],
    }
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description="Select a contiguous seed cell from an official zone manifest")
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--anchor-e", type=float, required=True)
    parser.add_argument("--anchor-n", type=float, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    payload = load_manifest(args.manifest)
    selected = select_seed(payload, args.anchor_e, args.anchor_n)
    result = one_cell_manifest(payload, selected, args.anchor_e, args.anchor_n)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"seed cell -> {selected['id']} ({selected['seed_distance_m']} m from anchor)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
