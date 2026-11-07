#!/usr/bin/env python3
"""Fetch and build one complete Grand Bruxelles UrbIS cell.

Pipeline:
  EPSG:31370 bbox -> official UrbIS WFS layers -> compact working GeoJSON ->
  deduplicated building/surface runtime + clipped road/tram/train network runtime
  aligned to the current Godot/OSM world.

The working extracts preserve the bbox response geometry. Rail layers are
immediately pruned by authoritative UrbIS TYPE (TW/RW) because the public WFS
layers overlap; the before/after counts are retained in provenance metadata.
Runtime geometry is derived and never edited back into the working extracts.
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

from fetch_urbis_wfs_bbox import DEFAULT_LAYERS, parse_bbox, request_layer
from make_urbis_cell_runtime import build_runtime
from make_urbis_network_cell_runtime import build_runtime as build_network_runtime


def write_json(path: Path, payload: dict[str, Any], compact: bool = True) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    if compact:
        text = json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n"
    else:
        text = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
    temporary.write_text(text, encoding="utf-8")
    temporary.replace(path)


def build_cell(
    cell_id: str,
    bbox: tuple[float, float, float, float],
    output_dir: Path,
    retries: int = 4,
) -> dict[str, Any]:
    raw_dir = output_dir / "raw"
    runtime_dir = output_dir / "runtime"
    layer_documents: dict[str, dict[str, Any]] = {}
    layer_stats: dict[str, dict[str, Any]] = {}

    for short_name, layer_name in DEFAULT_LAYERS.items():
        document = request_layer(layer_name, bbox, max(1, retries))
        document["grand_bruxelles_source"] = {
            "authority": "Paradigm / Brussels-Capital Region",
            "service": "UrbIS WFS",
            "layer": layer_name,
            "crs": "EPSG:31370",
            "bbox": list(bbox),
            "cell_id": cell_id,
        }
        layer_documents[short_name] = document
        raw_path = raw_dir / f"{short_name}.geojson"
        write_json(raw_path, document)
        layer_stats[short_name] = {
            "wfs_name": layer_name,
            "features": len(document.get("features", [])),
            "feature_filter": document.get("grand_bruxelles_filter"),
            "file": str(raw_path.relative_to(output_dir)),
        }

    runtime = build_runtime(
        layer_documents["buildings"],
        layer_documents["street_surfaces"],
        bbox,
        cell_id,
    )
    runtime_path = runtime_dir / "cell.game.json"
    write_json(runtime_path, runtime)

    network_runtime = build_network_runtime(
        layer_documents["street_axes"],
        layer_documents["tram_network"],
        layer_documents["train_network"],
        bbox,
        cell_id,
    )
    network_path = runtime_dir / "network.game.json"
    write_json(network_path, network_runtime)

    manifest = {
        "format": "grand-bruxelles-urbis-built-cell-v1",
        "cell_id": cell_id,
        "crs": "EPSG:31370",
        "bbox": list(bbox),
        "layers": layer_stats,
        "runtime": {
            "geometry_file": str(runtime_path.relative_to(output_dir)),
            "geometry_stats": runtime["stats"],
            "geometry_format": runtime["format"],
            "network_file": str(network_path.relative_to(output_dir)),
            "network_stats": network_runtime["stats"],
            "network_format": network_runtime["format"],
        },
    }
    write_json(output_dir / "manifest.json", manifest, compact=False)
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description="Fetch and build one official UrbIS game cell")
    parser.add_argument("--cell-id", required=True)
    parser.add_argument("--bbox", type=parse_bbox, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--retries", type=int, default=4)
    args = parser.parse_args()

    manifest = build_cell(args.cell_id, args.bbox, args.output_dir, args.retries)
    print(
        f"{args.cell_id}: geometry {manifest['runtime']['geometry_stats']} / "
        f"network {manifest['runtime']['network_stats']} -> {args.output_dir}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
