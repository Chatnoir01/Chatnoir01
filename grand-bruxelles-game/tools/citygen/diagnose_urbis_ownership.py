#!/usr/bin/env python3
"""Read-only diagnostic for canonical 500 m ownership failures in UrbIS GeoJSON."""
from __future__ import annotations

import argparse
import importlib.util
import json
import math
from collections import Counter
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("materialize", HERE / "materialize_urbis_source_cell.py")
mod = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(mod)


def failure_reason(feature: dict[str, Any]) -> str | None:
    if mod.owner_cell(feature) is not None:
        return None
    geom = feature.get("geometry")
    if not isinstance(geom, dict):
        return "missing_geometry"
    geom_type = geom.get("type")
    if geom_type != "Polygon":
        return f"unsupported_geometry_type:{geom_type}"
    coords = geom.get("coordinates")
    if not isinstance(coords, list) or not coords:
        return "missing_polygon_coordinates"
    ring = coords[0]
    if not isinstance(ring, list):
        return "invalid_exterior_ring"
    if len(ring) < 4:
        return "short_exterior_ring"
    for point in ring:
        if not isinstance(point, list) or len(point) < 2:
            return "invalid_point_shape"
        try:
            x, y = float(point[0]), float(point[1])
        except (TypeError, ValueError):
            return "non_numeric_coordinate"
        if not math.isfinite(x) or not math.isfinite(y):
            return "non_finite_coordinate"
    # The production centroid only has one remaining fail path for a structurally
    # valid Polygon: fewer than three distinct points after removing closure.
    points = [(float(p[0]), float(p[1])) for p in ring]
    if len(points) >= 2 and points[0] == points[-1]:
        points.pop()
    if len(points) < 3:
        return "insufficient_exterior_points"
    return "unexpected_centroid_failure"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("geojson", type=Path)
    args = ap.parse_args()
    payload = json.loads(args.geojson.read_text(encoding="utf-8"))
    failures = []
    counts = Counter()
    geometry_types = Counter()
    for feature in payload.get("features") or []:
        geom = feature.get("geometry") or {}
        geometry_types[str(geom.get("type"))] += 1
        reason = failure_reason(feature)
        if reason is None:
            continue
        props = feature.get("properties") or {}
        inspire_id = str(props.get("INSPIRE_ID") or feature.get("id") or "unknown")
        failures.append({"id": inspire_id, "reason": reason, "geometry_type": geom.get("type")})
        counts[reason] += 1
    print("URBIS_OWNERSHIP_DIAGNOSTIC", "features=", len(payload.get("features") or []), "geometry_types=", dict(sorted(geometry_types.items())), "invalid=", len(failures), "reasons=", dict(sorted(counts.items())))
    for row in failures:
        print("INVALID_OWNERSHIP", json.dumps(row, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
