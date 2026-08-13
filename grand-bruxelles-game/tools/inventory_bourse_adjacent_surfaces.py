#!/usr/bin/env python3
"""Inventory official StreetSurface neighbors around the locked Bourse forecourt slice.

Evidence/QA only. This tool deliberately does not promote any neighbor into runtime.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
import extract_bourse_urbis_surfaces as base


def _bbox(rings: list[list[list[float]]]) -> list[float]:
    pts = [p for ring in rings for p in ring]
    return [
        min(p[0] for p in pts),
        min(p[1] for p in pts),
        max(p[0] for p in pts),
        max(p[1] for p in pts),
    ]


def _union_bbox(surfaces: list[dict[str, Any]]) -> list[float]:
    boxes = [_bbox(item["source_rings_epsg31370"]) for item in surfaces]
    return [
        min(box[0] for box in boxes),
        min(box[1] for box in boxes),
        max(box[2] for box in boxes),
        max(box[3] for box in boxes),
    ]


def _bbox_gap_m(a: list[float], b: list[float]) -> float:
    dx = max(a[0] - b[2], b[0] - a[2], 0.0)
    dy = max(a[1] - b[3], b[1] - a[3], 0.0)
    return math.hypot(dx, dy)


def _bbox_center(box: list[float]) -> tuple[float, float]:
    return ((box[0] + box[2]) * 0.5, (box[1] + box[3]) * 0.5)


def inventory_neighbors(
    payload: dict[str, Any],
    transform: tuple[float, float, float, float],
) -> tuple[list[dict[str, Any]], list[float]]:
    targets = base.extract_target_surfaces(payload, transform)
    target_box = _union_bbox(targets)
    inventory: list[dict[str, Any]] = []

    for feature in payload.get("features", []):
        if not isinstance(feature, dict):
            continue
        props = feature.get("properties")
        if not isinstance(props, dict):
            continue
        inspire_id = str(props.get("INSPIRE_ID", ""))
        if not inspire_id or inspire_id in base.TARGET_IDS:
            continue
        try:
            source_rings = base._polygon_rings(feature.get("geometry"))
        except ValueError:
            continue
        box = _bbox(source_rings)
        cx, cy = _bbox_center(box)
        world_rings = [
            [base.to_world_xz(point[0], point[1], transform) for point in ring]
            for ring in source_rings
        ]
        inventory.append(
            {
                "inspire_id": inspire_id,
                "type_uninterpreted": props.get("TYPE"),
                "area_m2": props.get("AREA"),
                "level": props.get("LVL"),
                "street_name_fr": props.get("STRNAMEFRE"),
                "street_name_nl": props.get("STRNAMEDUT"),
                "source_bbox_epsg31370": box,
                "target_bbox_gap_m": _bbox_gap_m(box, target_box),
                "bourse_center_distance_m": math.hypot(
                    cx - base.BOURSE_CENTER[0], cy - base.BOURSE_CENTER[1]
                ),
                "source_rings_epsg31370": source_rings,
                "world_rings_xz": world_rings,
            }
        )

    inventory.sort(
        key=lambda item: (
            float(item["target_bbox_gap_m"]),
            float(item["bourse_center_distance_m"]),
            item["inspire_id"],
        )
    )
    return inventory, target_box


def build_output(
    payload: dict[str, Any],
    response_sha256: str,
    transform_path: Path = base.AXIS_EVIDENCE,
) -> dict[str, Any]:
    transform = base.load_world_transform(transform_path)
    inventory, target_box = inventory_neighbors(payload, transform)
    return {
        "schema": "grand-bruxelles-bourse-streetsurface-neighbor-inventory-v1",
        "source": {
            "provider": "Paradigm / Brussels-Capital Region",
            "dataset": "UrbIS - Transport networks",
            "dataset_id": base.TRANSPORT_DATASET_ID,
            "service": "UrbIS WFS",
            "url": base.WFS_URL,
            "layer": base.LAYER,
            "crs": base.CRS,
            "request_bbox_epsg31370": list(base.probe_bbox()),
            "license": base.LICENSE,
            "license_url": base.LICENSE_URL,
            "accessed_at": base.ACCESSED_AT,
            "response_sha256": response_sha256,
        },
        "locked_target": "Place de la Bourse / Beursplein",
        "target_inspire_ids": sorted(base.TARGET_IDS),
        "target_union_bbox_epsg31370": target_box,
        "neighbor_inventory": inventory,
        "selection_policy": (
            "QA inventory only: sorted by exact source-polygon bbox gap to the already locked "
            "three Bourse surfaces. No distance threshold grants runtime promotion."
        ),
        "runtime_approved": False,
        "realism_complete": False,
        "next_step": (
            "inspect nearest official neighbors and promote only a small defensible contiguous "
            "surface slice before rerendering the fixed geotagged Bourse camera"
        ),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    payload, digest = base.fetch_live()
    output = build_output(payload, digest)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(output, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    nearest = output["neighbor_inventory"][:12]
    print(
        json.dumps(
            {
                "neighbor_count": len(output["neighbor_inventory"]),
                "nearest": [
                    {
                        "inspire_id": item["inspire_id"],
                        "gap_m": round(float(item["target_bbox_gap_m"]), 3),
                        "street_name_fr": item["street_name_fr"],
                        "street_name_nl": item["street_name_nl"],
                        "type_uninterpreted": item["type_uninterpreted"],
                        "area_m2": item["area_m2"],
                    }
                    for item in nearest
                ],
                "runtime_approved": output["runtime_approved"],
            },
            indent=2,
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
