#!/usr/bin/env python3
"""Extract Brussels City subzone polygons using a name schema proven by UrbIS.

The probe only needs to prove which property keys identify the mandatory Haren
and Neder-over-Heembeek targets. Additional reservation-only targets such as
Laeken may then be selected with the same proven property keys, but still must
exist as Polygon/MultiPolygon features in the same official layer.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

TOOLS_DIR = Path(__file__).resolve().parent
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

from extract_brussels_city_subzones import (
    FORMAT,
    extract_target_features,
    load_probe,
    proven_name_keys,
    proven_result,
    slug,
)
from probe_urbis_admin_layers import fetch_features


def build_outputs_v2(
    probe: dict[str, Any],
    document: dict[str, Any],
    requested_targets: list[str],
) -> tuple[dict[str, dict[str, Any]], dict[str, Any]]:
    result = proven_result(probe)
    layer = str(result["layer"])
    proof_targets = [str(target) for target in probe.get("targets", [])]
    if not proof_targets:
        raise ValueError("probe has no proof targets")
    name_keys = proven_name_keys(result, proof_targets)

    outputs: dict[str, dict[str, Any]] = {}
    targets_manifest: dict[str, Any] = {}
    for target in requested_targets:
        features = extract_target_features(document, target, name_keys)
        key = slug(target)
        outputs[key] = {
            "type": "FeatureCollection",
            "name": target,
            "crs": {"type": "name", "properties": {"name": "EPSG:31370"}},
            "features": features,
            "grand_bruxelles_source": {
                "authority": "Paradigm / Brussels-Capital Region",
                "service": "UrbIS WFS",
                "layer": layer,
                "crs": "EPSG:31370",
                "selection_target": target,
                "proven_name_property_keys": sorted(name_keys),
                "schema_proof_targets": proof_targets,
            },
        }
        targets_manifest[key] = {
            "target": target,
            "feature_count": len(features),
            "geometry_types": sorted({str((f.get("geometry") or {}).get("type") or "") for f in features}),
            "schema_proof_target": target in proof_targets,
        }

    manifest = {
        "format": FORMAT,
        "extractor_version": 2,
        "source_layer": layer,
        "crs": "EPSG:31370",
        "schema_proof_targets": proof_targets,
        "proven_name_property_keys": sorted(name_keys),
        "targets": targets_manifest,
        "production_gate": {
            "name_schema_proven": True,
            "all_requested_targets_exist_as_polygon_features": True,
            "cell_grid_generation_allowed": True,
        },
    }
    return outputs, manifest


def main() -> int:
    parser = argparse.ArgumentParser(description="Extract Brussels City subzones from a proven UrbIS name schema")
    parser.add_argument("--probe", type=Path, required=True)
    parser.add_argument("--target", action="append", required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()

    probe = load_probe(args.probe)
    layer = str(probe["proven_layers_matching_all_targets"][0])
    document = fetch_features(layer)
    outputs, manifest = build_outputs_v2(probe, document, list(args.target))

    args.output_dir.mkdir(parents=True, exist_ok=True)
    for key, output in outputs.items():
        path = args.output_dir / f"{key}.geojson"
        path.write_text(json.dumps(output, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
        print(f"{key}: {len(output['features'])} polygon feature(s) -> {path}")
    manifest_path = args.output_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"manifest -> {manifest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
