#!/usr/bin/env python3
"""Audit UrbIS building footprints and DSM-derived heights around the Atomium.

This is a diagnostic against landmark contamination: a DSM percentile can be
inflated when a non-building tall object overlaps or sits very close to an
official building footprint. The report does not mutate runtime data.
"""

from __future__ import annotations

import json
import math
from pathlib import Path

BUILDINGS = Path("data/urbis/laeken_jette/buildings.game.json")
HEIGHTS = Path("data/urbis/laeken_jette/building_heights_dsm.game.json")
OUTPUT = Path("data/sources/laeken_jette/atomium_neighbor_building_audit.json")
ATOMIUM_X = 224.92615906274295
ATOMIUM_Z = -6553.143077999353
RADIUS_M = 320.0


def positions(value):
    if isinstance(value, list):
        if len(value) >= 2 and isinstance(value[0], (int, float)) and isinstance(value[1], (int, float)):
            yield float(value[0]), float(value[1])
        else:
            for child in value:
                yield from positions(child)


def stats_for_geometry(geometry: dict):
    pts = list(positions(geometry.get("coordinates", [])))
    if not pts:
        return None
    xs = [p[0] for p in pts]
    zs = [p[1] for p in pts]
    cx = sum(xs) / len(xs)
    cz = sum(zs) / len(zs)
    return {
        "centroid_x": cx,
        "centroid_z": cz,
        "min_x": min(xs),
        "max_x": max(xs),
        "min_z": min(zs),
        "max_z": max(zs),
        "distance_to_atomium_m": math.hypot(cx - ATOMIUM_X, cz - ATOMIUM_Z),
        "bbox_distance_to_atomium_m": math.hypot(
            max(min_x := min(xs), min(ATOMIUM_X, max_x := max(xs))) - ATOMIUM_X,
            max(min_z := min(zs), min(ATOMIUM_Z, max_z := max(zs))) - ATOMIUM_Z,
        ),
    }


def main() -> int:
    buildings = json.loads(BUILDINGS.read_text(encoding="utf-8"))
    heights = json.loads(HEIGHTS.read_text(encoding="utf-8"))
    features = buildings.get("features", [])
    records = heights.get("records", [])
    if len(features) != len(records):
        raise SystemExit(f"feature/height mismatch {len(features)} != {len(records)}")

    nearby = []
    for index, (feature, record) in enumerate(zip(features, records)):
        if not isinstance(feature, dict):
            continue
        geometry = feature.get("geometry") or {}
        s = stats_for_geometry(geometry)
        if s is None or s["bbox_distance_to_atomium_m"] > RADIUS_M:
            continue
        props = feature.get("properties") or {}
        if not isinstance(props, dict):
            props = {}
        r = record if isinstance(record, dict) else {}
        nearby.append({
            "feature_index": index,
            "inspire_id": props.get("INSPIRE_ID"),
            "block_id": props.get("BLOCK_ID"),
            "area_m2": props.get("AREA"),
            **{k: round(v, 3) for k, v in s.items()},
            "height_m": r.get("height_m"),
            "height_quality": r.get("quality"),
            "sample_count": r.get("sample_count"),
            "p50_m": r.get("p50_m"),
            "p75_m": r.get("p75_m"),
            "p85_m": r.get("p85_m"),
            "p90_m": r.get("p90_m"),
            "spread_p90_p50_m": r.get("spread_p90_p50_m"),
            "ground_median_abs_m": r.get("ground_median_abs_m"),
            "surface_median_abs_m": r.get("surface_median_abs_m"),
        })

    nearby.sort(key=lambda item: (item["bbox_distance_to_atomium_m"], item["distance_to_atomium_m"]))
    suspicious = [
        item for item in nearby
        if item.get("height_m") is not None
        and float(item["height_m"]) >= 22.0
        and item["bbox_distance_to_atomium_m"] <= 180.0
    ]
    output = {
        "schema": 1,
        "atomium_game_xz": [ATOMIUM_X, ATOMIUM_Z],
        "radius_m": RADIUS_M,
        "nearby_count": len(nearby),
        "suspicious_tall_nearby_count": len(suspicious),
        "suspicious_tall_nearby": suspicious,
        "nearby_buildings": nearby,
        "policy": "Diagnostic only. Do not override a height without an independent source or a strong DSM contamination signature tied to the Atomium/non-building surface.",
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(output, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("ATOMIUM_BUILDING_AUDIT_OK", {"nearby": len(nearby), "suspicious": len(suspicious)})
    for item in suspicious:
        print("SUSPICIOUS", item)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
