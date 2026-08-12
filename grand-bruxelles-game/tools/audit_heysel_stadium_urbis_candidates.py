#!/usr/bin/env python3
"""Audit UrbIS building polygons around the King Baudouin Stadium.

The OpenStreetMap stadium centre is used only as a coarse selector. Candidate
geometry, area, bounds, centroids and oriented spans are derived exclusively
from the versioned UrbIS building dataset. Official stadium dimensions are a
validation reference, not replacement geometry. This script intentionally does
NOT choose a final stadium target: selection requires a separate deterministic
validation step.
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
    # EPSG:31370 transform of the rounded selector coordinate above.
    # It is deliberately low-authority and only narrows the UrbIS search.
    "easting": 147500.73,
    "northing": 176151.68,
}
OFFICIAL_STADIUM_DIMENSIONS = {
    "source": "King Baudouin Stadium official website — The Stadium in figures",
    "source_url": "https://kingbaudouinstadium.be/index.php/the-stadium/?lang=en",
    "length_m": 217.5,
    "width_m": 137.5,
    "roof_height_m": 36.0,
    "role": "dimension_validation_only_not_geometry_source",
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


def _convex_hull(points: list[tuple[float, float]]) -> list[tuple[float, float]]:
    unique = sorted(set(points))
    if len(unique) <= 2:
        return unique

    def cross(o: tuple[float, float], a: tuple[float, float], b: tuple[float, float]) -> float:
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower: list[tuple[float, float]] = []
    for point in unique:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], point) <= 0.0:
            lower.pop()
        lower.append(point)
    upper: list[tuple[float, float]] = []
    for point in reversed(unique):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], point) <= 0.0:
            upper.pop()
        upper.append(point)
    return lower[:-1] + upper[:-1]


def minimum_oriented_spans(points: list[tuple[float, float]]) -> dict[str, float] | None:
    hull = _convex_hull(points)
    if len(hull) < 2:
        return None
    best: dict[str, float] | None = None
    for index in range(len(hull)):
        x0, y0 = hull[index]
        x1, y1 = hull[(index + 1) % len(hull)]
        angle = math.atan2(y1 - y0, x1 - x0)
        cosine = math.cos(angle)
        sine = math.sin(angle)
        rotated_x = [x * cosine + y * sine for x, y in hull]
        rotated_y = [-x * sine + y * cosine for x, y in hull]
        span_x = max(rotated_x) - min(rotated_x)
        span_y = max(rotated_y) - min(rotated_y)
        rectangle_area = span_x * span_y
        if best is None or rectangle_area < best["rectangle_area_m2"]:
            best = {
                "length_m": max(span_x, span_y),
                "width_m": min(span_x, span_y),
                "rectangle_area_m2": rectangle_area,
                "axis_angle_deg": math.degrees(angle) % 180.0,
            }
    return best


def geometry_metrics(geometry: dict[str, Any]) -> dict[str, Any] | None:
    rings = list(_iter_outer_rings(geometry))
    if not rings:
        return None
    weighted_x = 0.0
    weighted_y = 0.0
    total_area = 0.0
    xs: list[float] = []
    ys: list[float] = []
    points: list[tuple[float, float]] = []
    for ring in rings:
        area, centroid_x, centroid_y = _ring_area_centroid(ring)
        if area <= 0.0:
            continue
        total_area += area
        weighted_x += centroid_x * area
        weighted_y += centroid_y * area
        for point in ring:
            x, y = float(point[0]), float(point[1])
            xs.append(x)
            ys.append(y)
            points.append((x, y))
    if total_area <= 0.0 or not xs:
        return None
    oriented = minimum_oriented_spans(points)
    return {
        "area_m2": total_area,
        "centroid_easting": weighted_x / total_area,
        "centroid_northing": weighted_y / total_area,
        "bbox": [min(xs), min(ys), max(xs), max(ys)],
        "oriented_spans": oriented,
    }


def _dimension_error_percent(oriented: dict[str, float] | None) -> float | None:
    if oriented is None:
        return None
    official_length = float(OFFICIAL_STADIUM_DIMENSIONS["length_m"])
    official_width = float(OFFICIAL_STADIUM_DIMENSIONS["width_m"])
    length_error = abs(float(oriented["length_m"]) - official_length) / official_length
    width_error = abs(float(oriented["width_m"]) - official_width) / official_width
    return (length_error + width_error) * 50.0


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
        oriented = metrics["oriented_spans"]
        dimension_error = _dimension_error_percent(oriented)
        candidate = {
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
        if oriented is not None:
            candidate["minimum_oriented_rectangle"] = {
                key: round(float(value), 3) for key, value in oriented.items()
            }
        if dimension_error is not None:
            candidate["mean_official_dimension_error_percent"] = round(dimension_error, 3)
        candidates.append(candidate)
    candidates.sort(
        key=lambda item: (
            float(item.get("mean_official_dimension_error_percent", 1e9)),
            float(item["distance_to_selector_m"]),
        )
    )
    return {
        "status": "candidate_geometry_audit_only_no_final_selection",
        "crs": CRS,
        "selector": SELECTOR,
        "official_stadium_dimensions": OFFICIAL_STADIUM_DIMENSIONS,
        "search_radius_m": radius_m,
        "minimum_candidate_area_m2": min_area_m2,
        "candidate_count": len(candidates),
        "candidates": candidates,
        "decision_rule": (
            "Do not select a final stadium target from proximity or dimension similarity alone. "
            "Use official dimensions only as a validation signal. Inspect the UrbIS candidate "
            "geometry against the OSM stadium envelope and official orthophoto context, then "
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
