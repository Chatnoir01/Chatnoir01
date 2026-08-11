#!/usr/bin/env python3
"""Extract named Brussels City polygon areas from a proven official dataset.

The probe must show exactly one official opendata.brussels.be dataset with a
Polygon/MultiPolygon match for every requested target. Geometry is accepted only
when its coordinate range is recognizable as WGS84 or Belgian Lambert 72.
WGS84 polygons are reprojected to EPSG:31370 with pyproj before cell generation.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

TOOLS_DIR = Path(__file__).resolve().parent
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

from probe_brussels_opendata_boundaries import (
    FORMAT as PROBE_FORMAT,
    fetch_all_records,
    geometry_bbox,
    iter_polygon_geometries,
    matching_scalar_fields,
)

FORMAT = "grand-bruxelles-opendata-subzone-boundaries-v1"
TARGET_DEFAULTS = ("quartier européen", "louise", "roosevelt", "bois de la cambre")


def slug(value: str) -> str:
    value = value.casefold().translate(str.maketrans({"é": "e", "è": "e", "ê": "e", "ë": "e"}))
    return re.sub(r"[^a-z0-9]+", "-", value).strip("-")


def load_probe(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("format") != PROBE_FORMAT:
        raise ValueError(f"unsupported polygon probe: {path}")
    return payload


def common_dataset(probe: dict[str, Any], targets: list[str]) -> str:
    mapping = probe.get("datasets_with_polygon_match_by_target") or {}
    sets: list[set[str]] = []
    for target in targets:
        values = mapping.get(target) or []
        if not values:
            raise ValueError(f"no dataset has polygon evidence for target {target!r}")
        sets.append(set(str(value) for value in values))
    common = set.intersection(*sets)
    if len(common) != 1:
        raise ValueError(f"expected exactly one common proven dataset for {targets}, got {sorted(common)}")
    return next(iter(common))


def coordinate_positions(value: object) -> list[tuple[float, float]]:
    result: list[tuple[float, float]] = []

    def walk(item: object) -> None:
        if not isinstance(item, list):
            return
        if len(item) >= 2 and isinstance(item[0], (int, float)) and isinstance(item[1], (int, float)):
            result.append((float(item[0]), float(item[1])))
            return
        for child in item:
            walk(child)

    walk(value)
    return result


def detect_crs(geometry: dict[str, Any]) -> str:
    bbox = geometry_bbox(geometry)
    if bbox is None:
        raise ValueError("geometry has no coordinate positions")
    min_x, min_y, max_x, max_y = bbox
    if -180 <= min_x <= 180 and -90 <= min_y <= 90 and -180 <= max_x <= 180 and -90 <= max_y <= 90:
        return "EPSG:4326"
    # Brussels Lambert72 coordinates live comfortably inside this wide Belgian range.
    if 0 <= min_x <= 300000 and 0 <= max_x <= 300000 and 0 <= min_y <= 300000 and 0 <= max_y <= 300000:
        return "EPSG:31370"
    raise ValueError(f"unrecognized geometry coordinate range: {bbox}")


def transform_coordinates(value: object, transformer: Any) -> object:
    if not isinstance(value, list):
        return value
    if len(value) >= 2 and isinstance(value[0], (int, float)) and isinstance(value[1], (int, float)):
        x, y = transformer.transform(float(value[0]), float(value[1]))
        rest = list(value[2:])
        return [x, y, *rest]
    return [transform_coordinates(child, transformer) for child in value]


def to_lambert72(geometry: dict[str, Any]) -> tuple[dict[str, Any], str]:
    source_crs = detect_crs(geometry)
    if source_crs == "EPSG:31370":
        return json.loads(json.dumps(geometry)), source_crs
    try:
        from pyproj import Transformer
    except ImportError as exc:
        raise RuntimeError("pyproj is required to transform WGS84 open-data polygons to EPSG:31370") from exc
    transformer = Transformer.from_crs("EPSG:4326", "EPSG:31370", always_xy=True)
    output = json.loads(json.dumps(geometry))
    output["coordinates"] = transform_coordinates(output["coordinates"], transformer)
    return output, source_crs


def target_features(records: list[dict[str, Any]], target: str) -> tuple[list[dict[str, Any]], set[str]]:
    features: list[dict[str, Any]] = []
    source_crs_values: set[str] = set()
    seen: set[str] = set()
    for index, record in enumerate(records):
        fields = matching_scalar_fields(record, target)
        if not fields:
            continue
        for path, geometry in iter_polygon_geometries(record):
            transformed, source_crs = to_lambert72(geometry)
            fingerprint = json.dumps(transformed, sort_keys=True, separators=(",", ":"))
            if fingerprint in seen:
                continue
            seen.add(fingerprint)
            source_crs_values.add(source_crs)
            features.append(
                {
                    "type": "Feature",
                    "id": f"{slug(target)}-{index}-{len(features)}",
                    "properties": {
                        "target": target,
                        "matching_fields": fields,
                        "source_record_index": index,
                        "source_geometry_path": path,
                        "source_crs": source_crs,
                    },
                    "geometry": transformed,
                }
            )
    if not features:
        raise ValueError(f"target {target!r} produced no named polygon geometry")
    return features, source_crs_values


def build_outputs(
    probe: dict[str, Any],
    records: list[dict[str, Any]],
    dataset_id: str,
    targets: list[str],
) -> tuple[dict[str, dict[str, Any]], dict[str, Any]]:
    outputs: dict[str, dict[str, Any]] = {}
    target_meta: dict[str, Any] = {}
    for target in targets:
        features, source_crs = target_features(records, target)
        key = slug(target)
        outputs[key] = {
            "type": "FeatureCollection",
            "name": target,
            "crs": {"type": "name", "properties": {"name": "EPSG:31370"}},
            "features": features,
            "grand_bruxelles_source": {
                "authority": "Brussels Open Data",
                "catalog": "https://opendata.brussels.be/",
                "dataset_id": dataset_id,
                "probe_format": probe.get("format"),
                "target": target,
                "output_crs": "EPSG:31370",
            },
        }
        target_meta[key] = {
            "target": target,
            "feature_count": len(features),
            "source_crs_values": sorted(source_crs),
            "output_crs": "EPSG:31370",
        }
    manifest = {
        "format": FORMAT,
        "dataset_id": dataset_id,
        "source": f"https://opendata.brussels.be/explore/dataset/{dataset_id}/",
        "targets": target_meta,
        "production_gate": {
            "same_dataset_polygon_name_proof": True,
            "coordinate_crs_detected": True,
            "reprojected_to_epsg31370": True,
            "cell_grid_generation_allowed": True,
            "license_still_requires_dataset_metadata_validation": True,
        },
    }
    return outputs, manifest


def main() -> int:
    parser = argparse.ArgumentParser(description="Extract proven Brussels open-data polygon subzones to EPSG:31370")
    parser.add_argument("--probe", type=Path, required=True)
    parser.add_argument("--target", action="append", default=[])
    parser.add_argument("--max-records", type=int, default=2500)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()

    targets = args.target or list(TARGET_DEFAULTS)
    probe = load_probe(args.probe)
    dataset_id = common_dataset(probe, targets)
    records, total = fetch_all_records(dataset_id, max(1, args.max_records))
    if total > args.max_records:
        raise ValueError(f"proven dataset {dataset_id} has {total} records, above --max-records {args.max_records}")
    outputs, manifest = build_outputs(probe, records, dataset_id, targets)
    manifest["source_record_count"] = total

    args.output_dir.mkdir(parents=True, exist_ok=True)
    for key, payload in outputs.items():
        path = args.output_dir / f"{key}.geojson"
        path.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
        print(key, "features=", len(payload["features"]), "->", path)
    manifest_path = args.output_dir / "opendata_manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("manifest ->", manifest_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
