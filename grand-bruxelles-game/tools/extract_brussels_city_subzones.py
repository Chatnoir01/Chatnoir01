#!/usr/bin/env python3
"""Extract proven Brussels City subzone polygons from an official UrbIS layer.

The input probe must have exactly one layer whose real attributes matched every
requested target. We derive the allowed name-property keys from that probe
rather than guessing a schema. Only Polygon/MultiPolygon features are accepted.
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

from probe_urbis_admin_layers import fetch_features, value_matches

PROBE_FORMAT = "grand-bruxelles-urbis-admin-layer-probe-v1"
FORMAT = "grand-bruxelles-city-subzone-boundaries-v1"
ALLOWED_GEOMETRIES = {"Polygon", "MultiPolygon"}


def slug(target: str) -> str:
    value = target.casefold().replace("'", " ")
    value = re.sub(r"[^a-z0-9]+", "-", value).strip("-")
    return value


def load_probe(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("format") != PROBE_FORMAT:
        raise ValueError(f"unsupported probe format: {path}")
    proven = payload.get("proven_layers_matching_all_targets")
    if not isinstance(proven, list) or len(proven) != 1:
        raise ValueError(f"expected exactly one proven layer, got {proven!r}")
    return payload


def proven_result(probe: dict[str, Any]) -> dict[str, Any]:
    layer = str(probe["proven_layers_matching_all_targets"][0])
    for result in probe.get("results", []):
        if isinstance(result, dict) and str(result.get("layer")) == layer:
            if result.get("status") != "inspected":
                raise ValueError(f"proven layer was not inspected: {layer}")
            return result
    raise ValueError(f"proven layer result missing: {layer}")


def proven_name_keys(result: dict[str, Any], targets: list[str]) -> set[str]:
    keys_by_target: list[set[str]] = []
    target_matches = result.get("target_matches") or {}
    for target in targets:
        matches = target_matches.get(target) or []
        keys: set[str] = set()
        for match in matches:
            if not isinstance(match, dict):
                continue
            props = match.get("matching_properties") or {}
            if isinstance(props, dict):
                keys.update(str(key) for key in props)
        if not keys:
            raise ValueError(f"probe contains no proven name property for target {target}")
        keys_by_target.append(keys)
    shared = set.intersection(*keys_by_target)
    if not shared:
        raise ValueError(f"targets do not share a proven name property: {keys_by_target}")
    return shared


def feature_matches_target(feature: dict[str, Any], target: str, name_keys: set[str]) -> bool:
    properties = feature.get("properties") or {}
    if not isinstance(properties, dict):
        return False
    return any(key in properties and value_matches(properties[key], target) for key in name_keys)


def extract_target_features(
    document: dict[str, Any],
    target: str,
    name_keys: set[str],
) -> list[dict[str, Any]]:
    selected: list[dict[str, Any]] = []
    for feature in document.get("features", []):
        if not isinstance(feature, dict) or not feature_matches_target(feature, target, name_keys):
            continue
        geometry = feature.get("geometry") or {}
        geometry_type = str(geometry.get("type") or "")
        if geometry_type not in ALLOWED_GEOMETRIES:
            raise ValueError(
                f"target {target} matched non-boundary geometry {geometry_type!r} in feature {feature.get('id')!r}"
            )
        selected.append(feature)
    if not selected:
        raise ValueError(f"no polygon feature matched target {target}")
    return selected


def build_outputs(
    probe: dict[str, Any],
    document: dict[str, Any],
    targets: list[str],
) -> tuple[dict[str, dict[str, Any]], dict[str, Any]]:
    result = proven_result(probe)
    layer = str(result["layer"])
    name_keys = proven_name_keys(result, targets)
    outputs: dict[str, dict[str, Any]] = {}
    manifest_targets: dict[str, Any] = {}

    for target in targets:
        features = extract_target_features(document, target, name_keys)
        key = slug(target)
        output = {
            "type": "FeatureCollection",
            "name": target,
            "crs": {
                "type": "name",
                "properties": {"name": "EPSG:31370"},
            },
            "features": features,
            "grand_bruxelles_source": {
                "authority": "Paradigm / Brussels-Capital Region",
                "service": "UrbIS WFS",
                "layer": layer,
                "crs": "EPSG:31370",
                "selection_target": target,
                "proven_name_property_keys": sorted(name_keys),
            },
        }
        outputs[key] = output
        manifest_targets[key] = {
            "target": target,
            "feature_count": len(features),
            "geometry_types": sorted({str((f.get("geometry") or {}).get("type") or "") for f in features}),
        }

    manifest = {
        "format": FORMAT,
        "source_layer": layer,
        "crs": "EPSG:31370",
        "proven_name_property_keys": sorted(name_keys),
        "targets": manifest_targets,
        "production_gate": {
            "attribute_identity_proven": True,
            "polygon_geometry_proven": True,
            "cell_grid_generation_allowed": True,
        },
    }
    return outputs, manifest


def main() -> int:
    parser = argparse.ArgumentParser(description="Extract Haren/Neder-over-Heembeek official subzone polygons from proven UrbIS admin layer")
    parser.add_argument("--probe", type=Path, required=True)
    parser.add_argument("--target", action="append", default=[])
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()

    probe = load_probe(args.probe)
    targets = args.target or list(probe.get("targets") or [])
    if not targets:
        parser.error("no targets supplied and probe contains no targets")
    layer = str(probe["proven_layers_matching_all_targets"][0])
    document = fetch_features(layer)
    outputs, manifest = build_outputs(probe, document, targets)

    args.output_dir.mkdir(parents=True, exist_ok=True)
    for key, output in outputs.items():
        path = args.output_dir / f"{key}.geojson"
        path.write_text(json.dumps(output, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
        print(f"{key}: {len(output['features'])} official polygon feature(s) -> {path}")
    manifest_path = args.output_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"subzone manifest -> {manifest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
