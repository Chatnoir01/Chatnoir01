#!/usr/bin/env python3
"""Normalize validated Nord OSM context into the shared environment runtime format.

Only source-backed point features are carried over. Roads/buildings/railways stay
owned by the official UrbIS City Machine runtime and are deliberately excluded.
"""
from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path

INPUT_FORMAT = "grand-bruxelles-osm-v1"
OUTPUT_FORMAT = "grand-bruxelles-osm-zone-environment-v1"
SUPPORTED = {"tree", "street_lamp", "bollard"}


def fail(message: str) -> None:
    raise SystemExit(f"NORD_OSM_ENVIRONMENT_FAIL {message}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    data = json.loads(args.input.read_text(encoding="utf-8"))
    if data.get("format") != INPUT_FORMAT:
        fail(f"format={data.get('format')!r}")

    points = []
    for row in data.get("environment_points", []):
        if not isinstance(row, dict):
            fail("non_object_environment_point")
        kind = str(row.get("kind", ""))
        if kind not in SUPPORTED:
            fail(f"unsupported_kind={kind!r}")
        position = row.get("position")
        if not isinstance(position, list) or len(position) < 2:
            fail(f"invalid_position osm_id={row.get('osm_id')}")
        points.append({
            "kind": kind,
            "osm_id": int(row.get("osm_id", 0)),
            "position": [float(position[0]), float(position[1])],
        })

    if not points:
        fail("environment_points=0")

    counts = Counter(row["kind"] for row in points)
    out = {
        "format": OUTPUT_FORMAT,
        "source": data.get("source", ""),
        "license": data.get("license", ""),
        "origin": data.get("origin", {}),
        "bounds_m": data.get("bounds_m", []),
        "environment_points": points,
        "stats": dict(sorted(counts.items())),
        "source_dimensions_measured": False,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(out, ensure_ascii=False, separators=(",", ":"), sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(
        f"NORD_OSM_ENVIRONMENT_OK points={len(points)} "
        f"counts={dict(sorted(counts.items()))} runtime_format={OUTPUT_FORMAT}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
