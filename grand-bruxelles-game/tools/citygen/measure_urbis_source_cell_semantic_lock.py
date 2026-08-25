#!/usr/bin/env python3
"""Measure deterministic semantic identity for one persisted UrbIS source cell.

Transport-level GeoServer Feature.id/FID values are intentionally excluded from
semantic identity because they have been observed to vary between equivalent WFS
responses. Complete geometry and properties remain locked. Raw file hashes are
retained as forensic evidence.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def stable_feature(feature: dict[str, Any]) -> dict[str, Any]:
    if not isinstance(feature, dict):
        raise ValueError("invalid GeoJSON feature")
    return {key: value for key, value in feature.items() if key != "id"}


def stable_feature_key(feature: dict[str, Any]) -> tuple[str, bytes]:
    properties = feature.get("properties") or {}
    inspire_id = str(properties.get("INSPIRE_ID") or "")
    return inspire_id, canonical_bytes(feature)


def measure_layer(path: Path) -> dict[str, Any]:
    raw = path.read_bytes()
    doc = json.loads(raw.decode("utf-8"))
    if doc.get("type") != "FeatureCollection" or not isinstance(doc.get("features"), list):
        raise ValueError(f"not a FeatureCollection: {path}")
    stable = [stable_feature(feature) for feature in doc["features"]]
    stable.sort(key=stable_feature_key)
    return {
        "features": len(stable),
        "raw_bytes": len(raw),
        "raw_forensic_sha256": sha256_bytes(raw),
        "semantic_features_sha256": sha256_bytes(canonical_bytes(stable)),
    }


def maturity_state(maturity: dict[str, Any]) -> str:
    if maturity.get("format") != "grand-bruxelles-cell-maturity-v1":
        raise ValueError("unexpected cell maturity format")
    block = maturity.get("maturity")
    if not isinstance(block, dict) or not isinstance(block.get("gates"), dict):
        raise ValueError("cell maturity contract missing maturity.gates")
    state = block.get("state")
    if state != "data_ready":
        raise ValueError(f"source cell must be data_ready, got {state!r}")
    gates = block["gates"]
    if gates.get("source_requirements") is not True or gates.get("verification") is not True or gates.get("crs") is not True:
        raise ValueError("source-cell data-ready gates are incomplete")
    for key in ("runtime_geometry", "collisions", "streaming", "terrain", "heights", "photo_match", "performance"):
        if gates.get(key) is not False:
            raise ValueError(f"source-only maturity rail unexpectedly open: {key}")
    return state


def measure_cell(root: Path) -> dict[str, Any]:
    manifest_path = root / "manifest.json"
    maturity_path = root / "maturity.json"
    if not manifest_path.is_file() or not maturity_path.is_file():
        raise ValueError("source cell requires manifest.json and maturity.json")
    manifest_raw = manifest_path.read_bytes()
    maturity_raw = maturity_path.read_bytes()
    manifest = json.loads(manifest_raw.decode("utf-8"))
    maturity = json.loads(maturity_raw.decode("utf-8"))
    state = maturity_state(maturity)
    if manifest.get("format") != "grand-bruxelles-urbis-source-cell-v1":
        raise ValueError("unexpected source-cell manifest format")
    if manifest.get("cell_id") != root.name:
        raise ValueError("cell directory/manifest identity mismatch")
    if manifest.get("crs") != "EPSG:31370":
        raise ValueError("source cell must stay EPSG:31370")
    if manifest.get("promotion") != "source_only_no_runtime_mutation":
        raise ValueError("source-cell promotion rail drift")
    expected_layers = {"buildings", "street_surfaces", "street_axes", "tram_network", "train_network"}
    layers = manifest.get("layers") or {}
    if set(layers) != expected_layers:
        raise ValueError(f"unexpected source-cell layer set: {sorted(layers)}")
    measured_layers: dict[str, Any] = {}
    for logical_name in sorted(expected_layers):
        spec = layers[logical_name]
        rel = spec.get("file")
        if not isinstance(rel, str) or not rel.startswith("raw/") or ".." in Path(rel).parts:
            raise ValueError(f"unsafe source-cell layer path: {logical_name}")
        measured = measure_layer(root / rel)
        if measured["features"] != int(spec.get("features", -1)):
            raise ValueError(f"manifest feature count drift: {logical_name}")
        measured_layers[logical_name] = {
            "wfs_name": spec.get("wfs_name"),
            "ownership": spec.get("ownership"),
            "file": rel,
            "ownership_filtered": int(spec.get("ownership_filtered", 0)),
            "invalid_ownership_features": int(spec.get("invalid_ownership_features", 0)),
            **measured,
        }
    stable = {
        "cell_id": manifest["cell_id"],
        "crs": manifest["crs"],
        "bbox": manifest["bbox"],
        "promotion": manifest["promotion"],
        "source_digest": manifest["source_digest"],
        "layers": {
            name: {
                "wfs_name": value["wfs_name"],
                "ownership": value["ownership"],
                "file": value["file"],
                "features": value["features"],
                "ownership_filtered": value["ownership_filtered"],
                "invalid_ownership_features": value["invalid_ownership_features"],
                "semantic_features_sha256": value["semantic_features_sha256"],
            }
            for name, value in sorted(measured_layers.items())
        },
    }
    return {
        "schema": "grand-bruxelles-urbis-source-cell-semantic-measurement-v1",
        "cell_id": manifest["cell_id"],
        "crs": manifest["crs"],
        "bbox": manifest["bbox"],
        "manifest_source_digest": manifest["source_digest"],
        "manifest_sha256": sha256_bytes(manifest_raw),
        "maturity_sha256": sha256_bytes(maturity_raw),
        "maturity_state": state,
        "layers": measured_layers,
        "source_semantic_sha256": sha256_bytes(canonical_bytes(stable)),
        "registration_authorized": False,
        "runtime_mount_authorized": False,
        "rendered_geometry_authorized": False,
        "collision_authorized": False,
        "safe_spawn_authorized": False,
        "jouable_promotion_authorized": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cell-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = measure_cell(args.cell_dir)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        "URBIS_SOURCE_CELL_SEMANTIC_MEASURED "
        f"cell={result['cell_id']} semantic_sha256={result['source_semantic_sha256']} "
        f"layers={len(result['layers'])}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
