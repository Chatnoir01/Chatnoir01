#!/usr/bin/env python3
"""Select the best seed cell from an official zone-cell manifest.

The default strategy chooses the cell whose rectangle is closest to a Lambert72
anchor. For branch boundaries such as Anderlecht next to the main Midi corridor,
``--exclude-containing-anchor`` prevents this workstream from materializing the
500 m cell that owns the shared control point, keeping branch ownership clean.
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


def validated_bbox(bbox: list[float]) -> tuple[float, float, float, float]:
    if len(bbox) != 4:
        raise ValueError("bbox must contain four coordinates")
    min_e, min_n, max_e, max_n = [float(value) for value in bbox]
    if min_e >= max_e or min_n >= max_n:
        raise ValueError("invalid bbox extent")
    return min_e, min_n, max_e, max_n


def point_in_bbox(e: float, n: float, bbox: list[float]) -> bool:
    min_e, min_n, max_e, max_n = validated_bbox(bbox)
    return min_e <= e <= max_e and min_n <= n <= max_n


def distance_point_to_bbox(e: float, n: float, bbox: list[float]) -> float:
    min_e, min_n, max_e, max_n = validated_bbox(bbox)
    nearest_e = min(max(e, min_e), max_e)
    nearest_n = min(max(n, min_n), max_n)
    return math.hypot(e - nearest_e, n - nearest_n)


def select_seed(
    payload: dict[str, Any],
    anchor_e: float,
    anchor_n: float,
    *,
    exclude_containing_anchor: bool = False,
) -> dict[str, Any]:
    ranked = []
    excluded_ids: list[str] = []
    for cell in payload["cells"]:
        if not isinstance(cell, dict) or "bbox" not in cell or "id" not in cell:
            continue
        if exclude_containing_anchor and point_in_bbox(anchor_e, anchor_n, cell["bbox"]):
            excluded_ids.append(str(cell["id"]))
            continue
        distance = distance_point_to_bbox(anchor_e, anchor_n, cell["bbox"])
        min_e, min_n, max_e, max_n = validated_bbox(cell["bbox"])
        center_e = (min_e + max_e) * 0.5
        center_n = (min_n + max_n) * 0.5
        center_distance = math.hypot(anchor_e - center_e, anchor_n - center_n)
        ranked.append((distance, center_distance, str(cell["id"]), cell))
    if not ranked:
        raise ValueError("manifest contains no selectable cells after exclusions")
    ranked.sort(key=lambda item: (item[0], item[1], item[2]))
    distance, _, _, selected = ranked[0]
    return {
        **selected,
        "seed_distance_m": round(distance, 3),
        "excluded_anchor_cell_ids": excluded_ids,
    }


def one_cell_manifest(
    payload: dict[str, Any],
    selected: dict[str, Any],
    anchor_e: float,
    anchor_n: float,
    *,
    exclude_containing_anchor: bool = False,
) -> dict[str, Any]:
    internal_keys = {"seed_distance_m", "excluded_anchor_cell_ids"}
    result = dict(payload)
    result["cells"] = [{key: value for key, value in selected.items() if key not in internal_keys}]
    result["cell_count"] = 1
    result["seed_selection"] = {
        "strategy": "nearest_bbox_to_lambert72_anchor",
        "anchor": [anchor_e, anchor_n],
        "exclude_containing_anchor": exclude_containing_anchor,
        "excluded_anchor_cell_ids": selected.get("excluded_anchor_cell_ids", []),
        "selected_cell_id": selected["id"],
        "distance_m": selected["seed_distance_m"],
    }
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description="Select a contiguous seed cell from an official zone manifest")
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--anchor-e", type=float, required=True)
    parser.add_argument("--anchor-n", type=float, required=True)
    parser.add_argument(
        "--exclude-containing-anchor",
        action="store_true",
        help="skip any cell containing the anchor, useful when that cell belongs to another workstream",
    )
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    payload = load_manifest(args.manifest)
    selected = select_seed(
        payload,
        args.anchor_e,
        args.anchor_n,
        exclude_containing_anchor=args.exclude_containing_anchor,
    )
    result = one_cell_manifest(
        payload,
        selected,
        args.anchor_e,
        args.anchor_n,
        exclude_containing_anchor=args.exclude_containing_anchor,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"seed cell -> {selected['id']} ({selected['seed_distance_m']} m from anchor)")
    if selected.get("excluded_anchor_cell_ids"):
        print("excluded reserved anchor cells:", ", ".join(selected["excluded_anchor_cell_ids"]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
