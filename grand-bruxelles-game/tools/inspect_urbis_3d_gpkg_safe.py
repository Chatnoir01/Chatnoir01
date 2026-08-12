#!/usr/bin/env python3
"""Inspect an official UrbIS 3D GeoPackage without mutating project data.

This is intentionally an evidence tool. It inventories every GPKG below a directory,
verifies layer CRS metadata, detects declared Z geometry, samples real coordinates and
records finite Z ranges. Raw source packages are never copied into the repository.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from typing import Any, Iterator

from osgeo import ogr, osr

SCHEMA = "grand-bruxelles-urbis-3d-gpkg-inventory-v1"
EXPECTED_EPSG = "31370"
DEFAULT_SAMPLE_FEATURES = 250
DEFAULT_MAX_COORDS_PER_FEATURE = 4000


def sha256_file(path: Path, chunk_size: int = 1024 * 1024) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(chunk_size)
            if not chunk:
                break
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


def geometry_has_z(geometry_type: int) -> bool:
    try:
        return bool(ogr.GT_HasZ(geometry_type))
    except AttributeError:
        name = ogr.GeometryTypeToName(geometry_type).lower()
        return "3d" in name or " z" in name or name.endswith("z")


def iter_geometry_z(geometry: ogr.Geometry | None, max_coords: int) -> Iterator[float]:
    if geometry is None or max_coords <= 0:
        return
    emitted = 0
    stack: list[ogr.Geometry] = [geometry]
    while stack and emitted < max_coords:
        current = stack.pop()
        child_count = current.GetGeometryCount()
        if child_count > 0:
            for index in range(child_count - 1, -1, -1):
                child = current.GetGeometryRef(index)
                if child is not None:
                    stack.append(child)
            continue
        point_count = current.GetPointCount()
        for index in range(point_count):
            if emitted >= max_coords:
                return
            point = current.GetPoint(index)
            if len(point) >= 3:
                z = float(point[2])
                if math.isfinite(z):
                    emitted += 1
                    yield z


def inspect_layer(layer: ogr.Layer, sample_features: int, max_coords_per_feature: int) -> dict[str, Any]:
    definition = layer.GetLayerDefn()
    geometry_type = definition.GetGeomType()
    spatial_ref = layer.GetSpatialRef()
    epsg = authority_code(spatial_ref)
    declared_has_z = geometry_has_z(geometry_type)
    feature_count = int(layer.GetFeatureCount(0))
    extent = None
    try:
        raw_extent = layer.GetExtent(False)
        if raw_extent is not None:
            extent = [float(value) for value in raw_extent]
    except Exception:
        extent = None

    z_min = math.inf
    z_max = -math.inf
    finite_z_count = 0
    nonzero_z_count = 0
    sampled_feature_count = 0
    layer.ResetReading()
    for feature in layer:
        if sampled_feature_count >= sample_features:
            break
        sampled_feature_count += 1
        geometry = feature.GetGeometryRef()
        for z in iter_geometry_z(geometry, max_coords_per_feature):
            finite_z_count += 1
            if abs(z) > 1.0e-9:
                nonzero_z_count += 1
            z_min = min(z_min, z)
            z_max = max(z_max, z)

    actual_has_finite_z = finite_z_count > 0
    actual_has_nonzero_z = nonzero_z_count > 0
    return {
        "name": layer.GetName(),
        "feature_count_fast": feature_count,
        "sampled_feature_count": sampled_feature_count,
        "geometry_type_code": int(geometry_type),
        "geometry_type_name": ogr.GeometryTypeToName(geometry_type),
        "declared_has_z": declared_has_z,
        "epsg": epsg,
        "crs_wkt": None if spatial_ref is None else spatial_ref.ExportToWkt(),
        "extent_xy": extent,
        "sample_z": {
            "finite_coordinate_count": finite_z_count,
            "nonzero_coordinate_count": nonzero_z_count,
            "actual_has_finite_z": actual_has_finite_z,
            "actual_has_nonzero_z": actual_has_nonzero_z,
            "min": None if not actual_has_finite_z else z_min,
            "max": None if not actual_has_finite_z else z_max,
            "range": None if not actual_has_finite_z else z_max - z_min,
        },
        "candidate_for_height_validation": bool(
            epsg == EXPECTED_EPSG
            and declared_has_z
            and actual_has_nonzero_z
        ),
    }


def inspect_gpkg(path: Path, sample_features: int, max_coords_per_feature: int) -> dict[str, Any]:
    dataset = ogr.Open(str(path), 0)
    if dataset is None:
        raise RuntimeError(f"GDAL/OGR could not open GeoPackage: {path}")
    layers = [
        inspect_layer(dataset.GetLayerByIndex(index), sample_features, max_coords_per_feature)
        for index in range(dataset.GetLayerCount())
    ]
    candidate_layers = [layer["name"] for layer in layers if layer["candidate_for_height_validation"]]
    return {
        "path": str(path),
        "size_bytes": path.stat().st_size,
        "sha256": sha256_file(path),
        "layer_count": len(layers),
        "candidate_layer_count": len(candidate_layers),
        "candidate_layers": candidate_layers,
        "layers": layers,
    }


def build_inventory(
    root: Path,
    selected_source: dict[str, Any] | None,
    sample_features: int,
    max_coords_per_feature: int,
) -> dict[str, Any]:
    gpkg_files = sorted(path for path in root.rglob("*.gpkg") if path.is_file())
    packages = [inspect_gpkg(path, sample_features, max_coords_per_feature) for path in gpkg_files]
    candidate_layer_count = sum(package["candidate_layer_count"] for package in packages)
    all_epsg = sorted(
        {
            str(layer["epsg"])
            for package in packages
            for layer in package["layers"]
            if layer.get("epsg")
        }
    )
    return {
        "schema": SCHEMA,
        "purpose": "Second-source height validation for Grand Bruxelles Game / Ixelles seed cell",
        "expected_crs": "EPSG:31370",
        "source_selection": selected_source or {},
        "inspection_policy": {
            "read_only": True,
            "sample_features_per_layer": sample_features,
            "max_coordinates_per_sampled_feature": max_coords_per_feature,
            "candidate_requires": [
                "EPSG:31370",
                "declared Z geometry",
                "sampled finite non-zero Z coordinates",
            ],
        },
        "gpkg_count": len(packages),
        "candidate_layer_count": candidate_layer_count,
        "observed_epsg_codes": all_epsg,
        "packages": packages,
        "usable_as_second_height_source": candidate_layer_count > 0,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--selected-source", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--sample-features", type=int, default=DEFAULT_SAMPLE_FEATURES)
    parser.add_argument("--max-coords-per-feature", type=int, default=DEFAULT_MAX_COORDS_PER_FEATURE)
    parser.add_argument("--require-usable", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    selected_source: dict[str, Any] | None = None
    if args.selected_source:
        selected_source = json.loads(args.selected_source.read_text(encoding="utf-8"))
    inventory = build_inventory(
        args.root,
        selected_source,
        max(1, args.sample_features),
        max(1, args.max_coords_per_feature),
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(inventory, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        "URBIS_3D_GPKG_INVENTORY:",
        "gpkg=", inventory["gpkg_count"],
        "candidate_layers=", inventory["candidate_layer_count"],
        "epsg=", inventory["observed_epsg_codes"],
        "usable=", inventory["usable_as_second_height_source"],
    )
    if args.require_usable and not inventory["usable_as_second_height_source"]:
        raise SystemExit("No EPSG:31370 layer with sampled non-zero Z was proven")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
