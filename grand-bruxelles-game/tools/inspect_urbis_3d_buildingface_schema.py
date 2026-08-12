#!/usr/bin/env python3
"""Profile the official UrbIS 3D BuildingFaces schema without inferring semantics.

This is a read-only evidence tool. It records field definitions and bounded sampled
cardinality/value evidence so later building-level matching can choose identifiers
and face semantics from observed source data rather than guesses.
"""

from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path
from typing import Any

from osgeo import ogr

SCHEMA = "grand-bruxelles-urbis3d-buildingfaces-schema-v1"
TARGET_LAYER = "BuildingFaces"
DEFAULT_SAMPLE_FEATURES = 2000
DEFAULT_MAX_EXAMPLES = 12


def json_safe(value: Any) -> Any:
    if value is None or isinstance(value, (bool, int, float, str)):
        return value
    return str(value)


def profile_layer(layer: ogr.Layer, sample_features: int, max_examples: int) -> dict[str, Any]:
    definition = layer.GetLayerDefn()
    field_defs: list[dict[str, Any]] = []
    counters: list[Counter[str]] = []
    non_null = []

    for index in range(definition.GetFieldCount()):
        field = definition.GetFieldDefn(index)
        field_defs.append(
            {
                "name": field.GetName(),
                "type_name": field.GetFieldTypeName(field.GetType()),
                "width": int(field.GetWidth()),
                "precision": int(field.GetPrecision()),
                "nullable": bool(field.IsNullable()),
                "unique_constraint": bool(field.IsUnique()),
                "default": field.GetDefault(),
            }
        )
        counters.append(Counter())
        non_null.append(0)

    sampled = 0
    layer.ResetReading()
    for feature in layer:
        if sampled >= sample_features:
            break
        sampled += 1
        for index, _field in enumerate(field_defs):
            if not feature.IsFieldSetAndNotNull(index):
                continue
            non_null[index] += 1
            value = json_safe(feature.GetField(index))
            counters[index][json.dumps(value, ensure_ascii=False, sort_keys=True)] += 1

    profiles: list[dict[str, Any]] = []
    for index, field in enumerate(field_defs):
        counter = counters[index]
        distinct = len(counter)
        filled = non_null[index]
        examples = []
        for encoded, count in counter.most_common(max_examples):
            examples.append({"value": json.loads(encoded), "sample_count": count})
        profiles.append(
            {
                **field,
                "sample_non_null": filled,
                "sample_distinct": distinct,
                "sample_fill_ratio": 0.0 if sampled == 0 else filled / sampled,
                "sample_uniqueness_ratio": 0.0 if filled == 0 else distinct / filled,
                "sample_examples": examples,
            }
        )

    return {
        "layer": layer.GetName(),
        "feature_count_fast": int(layer.GetFeatureCount(0)),
        "sampled_feature_count": sampled,
        "field_count": len(profiles),
        "fields": profiles,
    }


def inspect_root(root: Path, sample_features: int, max_examples: int) -> dict[str, Any]:
    packages = []
    for path in sorted(p for p in root.rglob("*.gpkg") if p.is_file()):
        dataset = ogr.Open(str(path), 0)
        if dataset is None:
            raise RuntimeError(f"GDAL/OGR could not open GeoPackage: {path}")
        layer = dataset.GetLayerByName(TARGET_LAYER)
        if layer is None:
            continue
        packages.append(
            {
                "path": str(path),
                "building_faces": profile_layer(layer, sample_features, max_examples),
            }
        )

    return {
        "schema": SCHEMA,
        "purpose": "Observe official UrbIS 3D BuildingFaces identifiers/semantics before per-building height matching",
        "policy": {
            "read_only": True,
            "target_layer": TARGET_LAYER,
            "sample_features": sample_features,
            "max_examples_per_field": max_examples,
            "semantic_inference": False,
            "runtime_approval": False,
        },
        "package_count_with_buildingfaces": len(packages),
        "packages": packages,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--sample-features", type=int, default=DEFAULT_SAMPLE_FEATURES)
    parser.add_argument("--max-examples", type=int, default=DEFAULT_MAX_EXAMPLES)
    parser.add_argument("--require-buildingfaces", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    evidence = inspect_root(args.root, max(1, args.sample_features), max(1, args.max_examples))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        "URBIS3D_BUILDINGFACES_SCHEMA:",
        "packages=", evidence["package_count_with_buildingfaces"],
        "fields=", [
            field["name"]
            for package in evidence["packages"]
            for field in package["building_faces"]["fields"]
        ],
    )
    if args.require_buildingfaces and not evidence["packages"]:
        raise SystemExit("No BuildingFaces layer found in selected official GeoPackage")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
