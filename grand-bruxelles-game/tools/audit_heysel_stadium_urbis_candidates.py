#!/usr/bin/env python3
"""Audit UrbIS building polygons around the King Baudouin Stadium.

The OpenStreetMap stadium centre is used only as a coarse selector. Candidate
geometry, area, bounds and centroids are derived exclusively from the versioned
UrbIS building dataset. This script intentionally does NOT choose a final
stadium target: that decision requires inspection of the authoritative
candidate set and a second validation step.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any, Iterable

CRS = "EPSG:31370"
SELECTOR = {
    "role": "coarse_selector_only_not_final_geometry",
    "source": "OpenStreetMap way 253875451 via Mapcarta lookup",
    "source_url": "https://www.openstreetmap.org/way/253875451",
    "latitude": 50.8957,
    "longitude": 4.33408,
    # EPSG:31370 transform of the above rounded selector coordinate.
    # It is deliberately low-authority and only narrows the UrbIS search.
    "easting": 147500.73,
    "northing": 176151.68,
}
DEFAULT_RADIUS_M = 260.0
DEFAULT_MIN_AREA_M2 = 350.0


def _iter_outer_rings(geometry: dict[str, Any]) -> Iterable[list[list[float]]]:
    geometry_type = geometry.get("type")
    coordinates = geometry.get("coordinates", [])
    if geometry_type == "Polygon" and coordinates:
        yield coordinates[0]
    elif geometry_type == "MultiPolygon":
        for polygon in coordinates:
            if polygon:
                yield polygon[0]


def _ring_area_centroid(ring: list[list[float]]) -> tuple[float, float, float]:
    if len(ring) < 4:
        return 0.0, 0.0, 0.0
    twice_area = 0.0
    centroid_x_numerator = 0.0
    centroid_y_numerator = 0.0
    for index in range(len(ring) - 1):
        x0, y0 = float(ring[index][0]), float(ring[index][1])
        x1, y1 = float(ring[index + 1][0]), float(ring[index + 1][1])
        cross = x0 * y1 - x1 * y0
        twice_area += cross
        centroid_x_numerator += (x0 + x1) * cross
        centroid_y_numerator += (y0 + y1) * cross
    if abs(twice_area) < 1e-9:
        xs = [float(point[0]) for point in ring[:-1]]
        ys = [float(point[1]) for point in ring[:-1]]
        return 0.0, sum(xs) / len(xs), sum(ys) / len(ys)
    area = abs(twice_area) * 0.5
    centroid_x = centroid_x_numerator / (3.0 * twice_area)
    centroid_y = centroid_y_numerator / (3.0 * twice_area)
    return area, centroid_x, centroid_y


def geometry_metrics(geometry: dict[str, Any]) -> dict[str, Any] | None:
    rings = list(_iter_outer_rings(geometry))
    if not rings:
        return None
    weighted_x = 0.0
    weighted_y = 0.0
    total_area = 0.0
    xs: list[float] = []
    ys: list[float] = []
    for ring in rings:
        area, centroid_x, centroid_y = _ring_area_centroid(ring)
        if area <= 0.0:
            continue
        total_area += area
        weighted_x += centroid_x * area
        weighted_y += centroid_y * area
        xs.extend(float(point[0]) for point in ring)
        ys.extend(float(point[1]) for point in ring)
    if total_area <= 0.0 or not xs:
        return None
    return {
        "area_m2": total_area,
        "centroid_easting": weighted_x / total_area,
        "centroid_northing": weighted_y / total_area,
        "bbox": [min(xs), min(ys), max(xs), max(ys)],
    }


def build_audit(
    feature_collection: dict[str, Any],
    radius_m: float = DEFAULT_RADIUS_M,
    min_area_m2: float = DEFAULT_MIN_AREA_M2,
) -> dict[str, Any]:
    selector_e = float(SELECTOR["easting"])
    selector_n = float(SELECTOR["northing"])
    candidates: list[dict[str, Any]] = []
    for feature_index, feature in enumerate(feature_collection.get("features", [])):
        metrics = geometry_metrics(feature.get("geometry", {}))
        if metrics is None or float(metrics["area_m2"]) < min_area_m2:
            continue
        distance = math.hypot(
            float(metrics["centroid_easting"]) - selector_e,
            float(metrics["centroid_northing"]) - selector_n,
        )
        if distance > radius_m:
            continue
        properties = feature.get("properties", {})
        candidates.append(
            {
                "feature_index": feature_index,
                "feature_id": feature.get("id"),
                "distance_to_selector_m": round(distance, 3),
                "area_m2": round(float(metrics["area_m2"]), 3),
                "centroid_lambert72": [
                    round(float(metrics["centroid_easting"]), 3),
                    round(float(metrics["centroid_northing"]), 3),
                ],
                "bbox_lambert72": [round(float(value), 3) for value in metrics["bbox"]],
                "properties": properties,
            }
        )
    candidates.sort(key=lambda item: (item["distance_to_selector_m"], -item["area_m2"]))
    return {
        "status": "candidate_geometry_audit_only_no_final_selection",
        "crs": CRS,
        "selector": SELECTOR,
        "search_radius_m": radius_m,
        "minimum_candidate_area_m2": min_area_m2,
        "candidate_count": len(candidates),
        "candidates": candidates,
        "decision_rule": (
            "Do not select a final stadium target from proximity alone. Inspect the UrbIS "
            "candidate geometry against the OSM stadium envelope and orthophoto context, then "
            "record the selected UrbIS feature set in a separate deterministic validation step."
        ),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--buildings",
        default="grand-bruxelles-game/data/urbis/laeken_jette/buildings.geojson",
    )
    parser.add_argument("--output", default="")
    parser.add_argument("--radius-m", type=float, default=DEFAULT_RADIUS_M)
    parser.add_argument("--min-area-m2", type=float, default=DEFAULT_MIN_AREA_M2)
    args = parser.parse_args()

    feature_collection = json.loads(Path(args.buildings).read_text(encoding="utf-8"))
    audit = build_audit(feature_collection, args.radius_m, args.min_area_m2)
    encoded = json.dumps(audit, ensure_ascii=False, indent=2, sort_keys=True)
    if args.output:
        Path(args.output).write_text(encoded + "\n", encoding="utf-8")
    print(encoded)
    if audit["candidate_count"] == 0:
        raise SystemExit("HEYSEL_STADIUM_URBIS_AUDIT_FAIL: no plausible UrbIS building candidates")
    print(f"HEYSEL_STADIUM_URBIS_AUDIT_OK: {audit['candidate_count']} candidates")


if __name__ == "__main__":
    main()
