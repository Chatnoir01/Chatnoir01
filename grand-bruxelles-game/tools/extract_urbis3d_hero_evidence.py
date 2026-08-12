#!/usr/bin/env python3
"""Bridge one official UrbIS 2D building footprint to UrbIS 3D BuildingFaces.

Identity is deliberately conservative:
1. Find the requested building in an official EPSG:31370 WFS GeoJSON by a known
   source identifier (for Bourse: 8186511 / building/1751663).
2. Group nearby 3D faces by BUSOLID_ID.
3. Compare each solid's GROUNDSURFACE plan geometry with the official 2D footprint.
4. Accept a single solid only when geometric overlap clears explicit coverage and
   IoU thresholds with a uniqueness margin.

The output is evidence only. It never sets runtime_approved=true.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from typing import Any, Iterable

from osgeo import ogr, osr

EXPECTED_EPSG = "31370"
SCHEMA = "grand-bruxelles-urbis3d-hero-evidence-v2"
DEFAULT_MIN_COVERAGE = 0.80
DEFAULT_MIN_IOU = 0.70
DEFAULT_MIN_MARGIN = 0.10


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def authority_code(spatial_ref: osr.SpatialReference | None) -> str | None:
    if spatial_ref is None:
        return None
    clone = spatial_ref.Clone()
    try:
        clone.AutoIdentifyEPSG()
    except Exception:
        pass
    for target in (None, "PROJCS", "GEOGCS"):
        try:
            code = clone.GetAuthorityCode(target)
        except Exception:
            code = None
        if code:
            return str(code)
    return None


def iter_z(geometry: ogr.Geometry | None) -> Iterable[float]:
    if geometry is None:
        return
    stack = [geometry]
    while stack:
        current = stack.pop()
        if current.GetGeometryCount() > 0:
            for index in range(current.GetGeometryCount()):
                child = current.GetGeometryRef(index)
                if child is not None:
                    stack.append(child)
            continue
        for index in range(current.GetPointCount()):
            point = current.GetPoint(index)
            if len(point) >= 3 and math.isfinite(float(point[2])):
                yield float(point[2])


def summarize_z(values: list[float]) -> dict[str, Any]:
    if not values:
        return {"count": 0, "min": None, "max": None, "span": None}
    return {
        "count": len(values),
        "min": min(values),
        "max": max(values),
        "span": max(values) - min(values),
    }


def geojson_properties(feature: dict[str, Any]) -> dict[str, Any]:
    properties = feature.get("properties")
    return properties if isinstance(properties, dict) else {}


def values_match(properties: dict[str, Any], tokens: list[str]) -> bool:
    folded = [str(value).casefold() for value in properties.values() if value is not None]
    return any(any(token.casefold() in value for value in folded) for token in tokens)


def load_official_footprint(path: Path, tokens: list[str]) -> tuple[ogr.Geometry, dict[str, Any]]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    crs_text = json.dumps(payload.get("crs", {}), sort_keys=True)
    if crs_text not in ("{}", "null") and "31370" not in crs_text:
        raise ValueError(f"official footprint GeoJSON does not declare EPSG:31370: {crs_text}")

    matches: list[dict[str, Any]] = []
    for feature in payload.get("features", []):
        if isinstance(feature, dict) and values_match(geojson_properties(feature), tokens):
            matches.append(feature)
    if len(matches) != 1:
        raise ValueError(f"expected exactly one official 2D building match, found {len(matches)}")

    geometry_json = matches[0].get("geometry")
    geometry = ogr.CreateGeometryFromJson(json.dumps(geometry_json)) if geometry_json else None
    if geometry is None or geometry.IsEmpty():
        raise ValueError("matched official 2D building has no usable geometry")
    geometry.FlattenTo2D()
    if geometry.GetArea() <= 1.0:
        raise ValueError("matched official 2D building footprint area is implausibly small")
    return geometry, geojson_properties(matches[0])


def feature_properties(feature: ogr.Feature) -> dict[str, str]:
    properties: dict[str, str] = {}
    definition = feature.GetDefnRef()
    for index in range(definition.GetFieldCount()):
        value = feature.GetField(index)
        if value is not None:
            properties[definition.GetFieldDefn(index).GetName()] = str(value)
    return properties


def property_casefold(properties: dict[str, str], key: str) -> str:
    for name, value in properties.items():
        if name.casefold() == key.casefold():
            return value
    return ""


def union_geometries(geometries: list[ogr.Geometry]) -> ogr.Geometry | None:
    if not geometries:
        return None
    result = geometries[0].Clone()
    result.FlattenTo2D()
    for geometry in geometries[1:]:
        candidate = geometry.Clone()
        candidate.FlattenTo2D()
        result = result.Union(candidate)
    return result


def overlap_metrics(footprint: ogr.Geometry, ground: ogr.Geometry) -> dict[str, float]:
    intersection = footprint.Intersection(ground)
    intersection_area = float(intersection.GetArea()) if intersection is not None else 0.0
    footprint_area = float(footprint.GetArea())
    ground_area = float(ground.GetArea())
    union_area = footprint_area + ground_area - intersection_area
    return {
        "footprint_area_m2": footprint_area,
        "ground_area_m2": ground_area,
        "intersection_area_m2": intersection_area,
        "coverage": intersection_area / footprint_area if footprint_area > 0 else 0.0,
        "iou": intersection_area / union_area if union_area > 0 else 0.0,
    }


def extract(
    root: Path,
    footprint_geojson: Path,
    tokens: list[str],
    min_coverage: float = DEFAULT_MIN_COVERAGE,
    min_iou: float = DEFAULT_MIN_IOU,
    min_margin: float = DEFAULT_MIN_MARGIN,
) -> dict[str, Any]:
    footprint, footprint_properties = load_official_footprint(footprint_geojson, tokens)
    min_x, max_x, min_y, max_y = footprint.GetEnvelope()
    pad = 10.0

    packages: list[dict[str, Any]] = []
    solids: dict[str, dict[str, Any]] = {}
    diagnostic_faces = 0

    for path in sorted(p for p in root.rglob("*.gpkg") if p.is_file()):
        dataset = ogr.Open(str(path), 0)
        if dataset is None:
            continue
        package = {"path": str(path), "size_bytes": path.stat().st_size, "sha256": sha256_file(path)}
        packages.append(package)
        for layer_index in range(dataset.GetLayerCount()):
            layer = dataset.GetLayerByIndex(layer_index)
            if authority_code(layer.GetSpatialRef()) != EXPECTED_EPSG:
                continue
            layer.SetSpatialFilterRect(min_x - pad, min_y - pad, max_x + pad, max_y + pad)
            for feature in layer:
                geometry = feature.GetGeometryRef()
                z_values = list(iter_z(geometry))
                if geometry is None or not z_values:
                    continue
                properties = feature_properties(feature)
                solid_id = property_casefold(properties, "BUSOLID_ID")
                face_type = property_casefold(properties, "TYPE").upper()
                if not solid_id:
                    diagnostic_faces += 1
                    continue
                record = solids.setdefault(
                    solid_id,
                    {
                        "busolid_id": solid_id,
                        "package_sha256": package["sha256"],
                        "face_count": 0,
                        "face_types": {},
                        "all_z": [],
                        "ground_z": [],
                        "roof_z": [],
                        "ground_geometries": [],
                    },
                )
                record["face_count"] += 1
                record["face_types"][face_type] = int(record["face_types"].get(face_type, 0)) + 1
                record["all_z"].extend(z_values)
                if face_type == "GROUNDSURFACE":
                    record["ground_z"].extend(z_values)
                    record["ground_geometries"].append(geometry.Clone())
                elif face_type == "ROOFSURFACE":
                    record["roof_z"].extend(z_values)
            layer.SetSpatialFilter(None)

    candidates: list[dict[str, Any]] = []
    for solid_id, record in solids.items():
        ground = union_geometries(record.pop("ground_geometries"))
        if ground is None or ground.IsEmpty():
            continue
        metrics = overlap_metrics(footprint, ground)
        candidate = {
            "busolid_id": solid_id,
            "package_sha256": record["package_sha256"],
            "face_count": record["face_count"],
            "face_types": record["face_types"],
            "overlap": metrics,
            "all_z": summarize_z(record["all_z"]),
            "ground_z": summarize_z(record["ground_z"]),
            "roof_z": summarize_z(record["roof_z"]),
        }
        ground_min = candidate["ground_z"]["min"]
        roof_max = candidate["roof_z"]["max"]
        candidate["ground_to_roof_max_m"] = (
            float(roof_max) - float(ground_min)
            if ground_min is not None and roof_max is not None
            else None
        )
        candidates.append(candidate)

    candidates.sort(key=lambda item: (item["overlap"]["iou"], item["overlap"]["coverage"]), reverse=True)
    best = candidates[0] if candidates else None
    second_iou = candidates[1]["overlap"]["iou"] if len(candidates) > 1 else 0.0
    best_iou = best["overlap"]["iou"] if best else 0.0
    best_coverage = best["overlap"]["coverage"] if best else 0.0
    unique_margin = best_iou - second_iou
    identity_proven = bool(
        best
        and best_coverage >= min_coverage
        and best_iou >= min_iou
        and unique_margin >= min_margin
    )
    usable = bool(
        identity_proven
        and best
        and best["ground_z"]["count"] > 0
        and best["roof_z"]["count"] > 0
        and best["ground_to_roof_max_m"] is not None
        and best["ground_to_roof_max_m"] > 1.0
    )

    return {
        "schema": SCHEMA,
        "purpose": "Palais de la Bourse / Beurs official 2D-to-3D identity and height evidence",
        "identity_policy": "Official WFS 2D source identifier + unique ground-surface geometric overlap; proximity alone is never identity.",
        "expected_crs": "EPSG:31370",
        "identifier_tokens": tokens,
        "official_2d_source": {
            "path": str(footprint_geojson),
            "sha256": sha256_file(footprint_geojson),
            "properties": footprint_properties,
            "area_m2": float(footprint.GetArea()),
            "envelope": [min_x, max_x, min_y, max_y],
        },
        "thresholds": {
            "min_coverage": min_coverage,
            "min_iou": min_iou,
            "min_unique_iou_margin": min_margin,
        },
        "packages": packages,
        "candidate_count": len(candidates),
        "candidates": candidates[:20],
        "best_candidate": best,
        "second_best_iou": second_iou,
        "unique_iou_margin": unique_margin,
        "identity_proven": identity_proven,
        "usable_for_runtime_height_review": usable,
        "unkeyed_3d_face_count": diagnostic_faces,
        "runtime_approved": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--footprint-geojson", type=Path, required=True)
    parser.add_argument("--identifier", action="append", default=[])
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--min-coverage", type=float, default=DEFAULT_MIN_COVERAGE)
    parser.add_argument("--min-iou", type=float, default=DEFAULT_MIN_IOU)
    parser.add_argument("--min-margin", type=float, default=DEFAULT_MIN_MARGIN)
    parser.add_argument("--require-identity", action="store_true")
    args = parser.parse_args()

    result = extract(
        args.root,
        args.footprint_geojson,
        args.identifier,
        args.min_coverage,
        args.min_iou,
        args.min_margin,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    best = result.get("best_candidate") or {}
    print(
        "URBIS3D_HERO_EVIDENCE",
        "identity=", result["identity_proven"],
        "solid=", best.get("busolid_id"),
        "coverage=", (best.get("overlap") or {}).get("coverage"),
        "iou=", (best.get("overlap") or {}).get("iou"),
        "height=", best.get("ground_to_roof_max_m"),
    )
    if args.require_identity and not result["usable_for_runtime_height_review"]:
        raise SystemExit("Official 2D-to-3D Bourse identity/height evidence did not clear the conservative thresholds")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
