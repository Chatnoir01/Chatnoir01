#!/usr/bin/env python3
"""Summarise property keys/value distributions in the committed UrbIS street surfaces.

This is an evidence-only audit used to decide whether road/sidewalk/median curb
geometry can be generated from authoritative semantic classes. It does not alter
runtime geometry.
"""

from __future__ import annotations

import collections
import json
from pathlib import Path

SOURCE = Path("data/urbis/laeken_jette/street_surfaces.game.json")
OUTPUT = Path("data/sources/laeken_jette/street_surface_property_audit.json")


def normalise(value):
    if value is None:
        return "<null>"
    if isinstance(value, (str, int, float, bool)):
        return str(value)
    return f"<{type(value).__name__}>"


def main() -> int:
    document = json.loads(SOURCE.read_text(encoding="utf-8"))
    features = document.get("features", [])
    if not isinstance(features, list) or not features:
        raise SystemExit("No street surface features")

    key_counts = collections.Counter()
    value_counts: dict[str, collections.Counter] = collections.defaultdict(collections.Counter)
    geometry_counts = collections.Counter()
    samples = []

    for feature in features:
        if not isinstance(feature, dict):
            continue
        geometry = feature.get("geometry") or {}
        geometry_counts[str(geometry.get("type", "<none>"))] += 1
        props = feature.get("properties") or {}
        if not isinstance(props, dict):
            continue
        if len(samples) < 8:
            samples.append({k: props.get(k) for k in props})
        for key, value in props.items():
            key_counts[key] += 1
            value_counts[key][normalise(value)] += 1

    out = {
        "schema": 1,
        "source": str(SOURCE),
        "feature_count": len(features),
        "geometry_types": dict(geometry_counts),
        "property_keys": [
            {
                "key": key,
                "present_count": count,
                "distinct_count": len(value_counts[key]),
                "top_values": value_counts[key].most_common(30),
            }
            for key, count in key_counts.most_common()
        ],
        "sample_properties": samples,
        "policy": "Use semantic classes for curb/sidewalk generation only if the committed authoritative layer exposes an unambiguous relevant property; do not infer classes from colour or intuition.",
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("LAEKEN_STREET_SURFACE_AUDIT_OK", len(features), [x["key"] for x in out["property_keys"]])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
