#!/usr/bin/env python3
"""Audit deterministic ground-camera candidates around the Atomium.

This tool does not geolocate the reference photographer. It identifies candidate
benchmark camera points from authoritative UrbIS street-surface geometry and the
project's official DTM footprint, then excludes points falling inside UrbIS
building footprints. The result remains an audit until visual comparison is
performed.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Iterable, Sequence


def _rings(geometry: dict) -> Iterable[Sequence[Sequence[float]]]:
    kind = geometry.get("type")
    coords = geometry.get("coordinates", [])
    if kind == "Polygon":
        if coords:
            yield coords[0]
    elif kind == "MultiPolygon":
        for polygon in coords:
            if polygon:
                yield polygon[0]


def _centroid(ring: Sequence[Sequence[float]]) -> tuple[float, float]:
    pts = list(ring)
    if len(pts) > 1 and pts[0] == pts[-1]:
        pts = pts[:-1]
    if not pts:
        raise ValueError("empty ring")
    return (sum(float(p[0]) for p in pts) / len(pts), sum(float(p[1]) for p in pts) / len(pts))


def _point_in_ring(point: tuple[float, float], ring: Sequence[Sequence[float]]) -> bool:
    x, y = point
    inside = False
    pts = list(ring)
    if len(pts) < 3:
        return False
    j = len(pts) - 1
    for i, pi in enumerate(pts):
        xi, yi = float(pi[0]), float(pi[1])
        xj, yj = float(pts[j][0]), float(pts[j][1])
        if ((yi > y) != (yj > y)) and (x < (xj - xi) * (y - yi) / ((yj - yi) or 1e-12) + xi):
            inside = not inside
        j = i
    return inside


def _inside_any_building(point: tuple[float, float], buildings: list[dict]) -> bool:
    for feature in buildings:
        for ring in _rings(feature.get("geometry") or {}):
            if _point_in_ring(point, ring):
                return True
    return False


def audit(streets: dict, buildings: dict, dtm: dict, atomium_e: float, atomium_n: float,
          min_radius: float = 60.0, max_radius: float = 220.0, limit: int = 24) -> dict:
    bounds = dtm["bounds_epsg31370"]
    candidates = []
    building_features = buildings.get("features", [])
    for feature in streets.get("features", []):
        for ring in _rings(feature.get("geometry") or {}):
            e, n = _centroid(ring)
            if not (bounds["min_e"] <= e <= bounds["max_e"] and bounds["min_n"] <= n <= bounds["max_n"]):
                continue
            distance = math.hypot(e - atomium_e, n - atomium_n)
            if distance < min_radius or distance > max_radius:
                continue
            if _inside_any_building((e, n), building_features):
                continue
            azimuth = (math.degrees(math.atan2(e - atomium_e, n - atomium_n)) + 360.0) % 360.0
            candidates.append({
                "e": round(e, 3),
                "n": round(n, 3),
                "distance_to_atomium_m": round(distance, 3),
                "azimuth_from_atomium_deg": round(azimuth, 3),
                "street_feature_id": feature.get("id"),
            })
    candidates.sort(key=lambda c: (abs(c["distance_to_atomium_m"] - 120.0), c["azimuth_from_atomium_deg"]))
    selected = candidates[:limit]
    return {
        "schema": 1,
        "purpose": "candidate audit only; not photographer geolocation",
        "crs": "EPSG:31370",
        "authoritative_inputs": ["UrbIS street surfaces", "UrbIS building footprints", "official DTM bounds"],
        "selection_policy": {
            "min_radius_m": min_radius,
            "max_radius_m": max_radius,
            "exclude_building_footprints": True,
            "require_inside_dtm_bounds": True,
            "ranking": "closest to 120 m ground distance, deterministic azimuth tiebreak",
        },
        "candidate_count_before_limit": len(candidates),
        "candidates": selected,
        "status": "candidate_audit_ready_for_visual_comparison" if selected else "blocked_no_authoritative_candidate",
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--streets", required=True)
    ap.add_argument("--buildings", required=True)
    ap.add_argument("--dtm", required=True)
    ap.add_argument("--anchors", required=True)
    ap.add_argument("--output", required=True)
    args = ap.parse_args()
    streets = json.loads(Path(args.streets).read_text(encoding="utf-8"))
    buildings = json.loads(Path(args.buildings).read_text(encoding="utf-8"))
    dtm = json.loads(Path(args.dtm).read_text(encoding="utf-8"))
    anchors = json.loads(Path(args.anchors).read_text(encoding="utf-8"))
    atomium = next(a for a in anchors["anchors"] if a["id"] == "atomium")
    e, n = atomium["lambert72"]
    result = audit(streets, buildings, dtm, e, n)
    Path(args.output).parent.mkdir(parents=True, exist_ok=True)
    Path(args.output).write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(result["status"], result["candidate_count_before_limit"], len(result["candidates"]))


if __name__ == "__main__":
    main()
