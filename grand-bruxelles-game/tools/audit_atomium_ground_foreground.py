#!/usr/bin/env python3
"""Inventory source-grounded public trees in the Atomium ground-oblique view corridor.

The audit does not create missing vegetation or street furniture. It measures what
our already-vendored City of Brussels public-tree inventory can actually support
around the source-published camera-to-Atomium axis, and explicitly reports that
inventory incompleteness prevents treating missing records as proof of absence.
"""

from __future__ import annotations

import argparse
import json
import math
from collections import Counter
from pathlib import Path


DEFAULT_TREES = Path("data/environment/laeken_jette/official_city_trees.game.json")
DEFAULT_VIEWS = Path("data/reference/laeken_jette/photo_match_views.json")
DEFAULT_VIEW_ID = "atomium_ground_oblique_v1"


def _load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _view(doc: dict, view_id: str) -> dict:
    for item in doc.get("views", []):
        if item.get("id") == view_id:
            return item
    raise ValueError(f"view not found: {view_id}")


def audit(trees_doc: dict, view: dict, half_width_m: float = 70.0) -> dict:
    camera = view["camera_game_xz"]
    target = view["target_game_xyz"]
    cx, cz = float(camera[0]), float(camera[1])
    tx, tz = float(target[0]), float(target[2])
    ax, az = tx - cx, tz - cz
    distance = math.hypot(ax, az)
    if distance <= 0.0:
        raise ValueError("zero camera-to-target distance")
    ux, uz = ax / distance, az / distance
    # Perpendicular in the X/Z ground plane.
    px, pz = -uz, ux

    selected: list[dict] = []
    source_counts: Counter[str] = Counter()
    species_counts: Counter[str] = Counter()
    bands = {
        "foreground_0_100m": 0,
        "midground_100_220m": 0,
        "atomium_context_220m_to_target_plus_40m": 0,
    }

    for feature in trees_doc.get("features", []):
        if not isinstance(feature, dict):
            continue
        geometry = feature.get("geometry") or {}
        coords = geometry.get("coordinates") if isinstance(geometry, dict) else None
        if not isinstance(coords, list) or len(coords) < 2:
            continue
        x, z = float(coords[0]), float(coords[1])
        rx, rz = x - cx, z - cz
        along = rx * ux + rz * uz
        lateral = rx * px + rz * pz
        if along < -20.0 or along > distance + 40.0 or abs(lateral) > half_width_m:
            continue
        props = feature.get("properties") or {}
        if not isinstance(props, dict):
            props = {}
        species = str(props.get("species") or "non renseignée")
        source = str(props.get("source_fr") or "non renseigné")
        source_counts[source] += 1
        species_counts[species] += 1
        if along < 100.0:
            bands["foreground_0_100m"] += 1
        elif along < 220.0:
            bands["midground_100_220m"] += 1
        else:
            bands["atomium_context_220m_to_target_plus_40m"] += 1
        selected.append({
            "id": str(feature.get("id", "")),
            "game_xz": [round(x, 3), round(z, 3)],
            "along_axis_m": round(along, 3),
            "lateral_from_axis_m": round(lateral, 3),
            "species": species,
            "source": source,
        })

    selected.sort(key=lambda row: (row["along_axis_m"], abs(row["lateral_from_axis_m"]), row["id"]))
    return {
        "schema": 1,
        "view_id": view["id"],
        "method": "known public-tree points within a rectangular camera-to-Atomium ground corridor",
        "camera_game_xz": [cx, cz],
        "target_game_xz": [tx, tz],
        "camera_to_target_ground_distance_m": distance,
        "corridor_half_width_m": half_width_m,
        "corridor_along_range_m": [-20.0, distance + 40.0],
        "known_tree_count": len(selected),
        "distance_bands": bands,
        "source_counts": dict(sorted(source_counts.items())),
        "top_species": species_counts.most_common(20),
        "known_trees": selected,
        "limitations": [
            "City public-tree inventory is explicitly incomplete; missing points are not proof that a tree is absent.",
            "Tree positions/species are source-grounded, but current runtime dimensions are deterministic visual approximations.",
            "This audit does not establish fountain, bench, lamp-post, parked-car or pedestrian geometry.",
        ],
        "realism_use": "Use these known positions to assess whether existing official-tree coverage can support the flanking vegetation visible from the lawful reference. Seek orthophoto/lawful references for gaps; never fill them by intuition alone.",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--trees", type=Path, default=DEFAULT_TREES)
    parser.add_argument("--views", type=Path, default=DEFAULT_VIEWS)
    parser.add_argument("--view-id", default=DEFAULT_VIEW_ID)
    parser.add_argument("--half-width-m", type=float, default=70.0)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    result = audit(_load(args.trees), _view(_load(args.views), args.view_id), args.half_width_m)
    payload = json.dumps(result, indent=2, ensure_ascii=False, sort_keys=True) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(payload, encoding="utf-8")
    else:
        print(payload, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
