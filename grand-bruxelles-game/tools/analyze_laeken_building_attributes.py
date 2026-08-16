#!/usr/bin/env python3
"""Inventory UrbIS building property fields relevant to real 3D heights."""

from __future__ import annotations

import json
import math
from collections import Counter, defaultdict
from pathlib import Path

SOURCE = Path("data/urbis/laeken_jette/buildings.geojson")
OUTPUT = Path("data/sources/laeken_jette/urbis_building_attribute_inventory.json")
TOKENS = ("height", "haut", "level", "floor", "storey", "story", "elev", "alt", "z_", "zmin", "zmax", "roof")


def numeric(value):
    if isinstance(value, bool) or value is None:
        return None
    try:
        result = float(value)
    except (TypeError, ValueError):
        return None
    return result if math.isfinite(result) else None


def main() -> int:
    document = json.loads(SOURCE.read_text(encoding="utf-8"))
    features = document.get("features", [])
    key_counts: Counter[str] = Counter()
    values: dict[str, list[float]] = defaultdict(list)
    samples: dict[str, list[object]] = defaultdict(list)

    for feature in features:
        props = feature.get("properties") or {}
        if not isinstance(props, dict):
            continue
        for key, value in props.items():
            key_counts[key] += 1
            low = key.lower()
            if any(token in low for token in TOKENS):
                number = numeric(value)
                if number is not None:
                    values[key].append(number)
                if value is not None and len(samples[key]) < 12:
                    samples[key].append(value)

    relevant = {}
    for key in sorted(set(values) | set(samples)):
        nums = values.get(key, [])
        relevant[key] = {
            "present_features": key_counts[key],
            "numeric_count": len(nums),
            "numeric_min": min(nums) if nums else None,
            "numeric_max": max(nums) if nums else None,
            "numeric_mean": sum(nums) / len(nums) if nums else None,
            "samples": samples.get(key, []),
        }

    output = {
        "schema": 1,
        "source": "Paradigm UrbIS vector Buildings WFS clipped to Laeken phase 1",
        "feature_count": len(features),
        "all_property_keys": [
            {"key": key, "present_features": count}
            for key, count in sorted(key_counts.items())
        ],
        "height_related_fields": relevant,
        "decision_rule": "Only fields whose semantics and numeric range clearly represent metric building height or floor count may be consumed by the Godot builder. Otherwise the default height remains explicitly provisional until UrbIS Landscape/3D-derived heights are extracted.",
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(output, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("LAEKEN_BUILDING_ATTRIBUTES_OK", len(features), "relevant", list(relevant))
    for key, stats in relevant.items():
        print(key, stats)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
