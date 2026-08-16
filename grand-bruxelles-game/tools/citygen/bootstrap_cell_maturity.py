#!/usr/bin/env python3
"""Bootstrap a fail-closed maturity manifest from one authoritative CityGen source cell.

Only evidence already present in the source cell is promoted. Runtime, collisions,
streaming, terrain, heights, photo-match and performance remain false until their
independent gates produce proof. The output is deterministic and safe to persist on
the autonomous state branch; it never mutates Godot runtime data.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

FORMAT = "grand-bruxelles-cell-maturity-v1"
CRS = "EPSG:31370"
GATES = ("runtime_geometry", "collisions", "streaming", "terrain", "heights", "photo_match", "performance")


def _read(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def _digest(value: Any) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")).hexdigest()


def build(cell_dir: Path) -> dict[str, Any]:
    manifest_path = cell_dir / "manifest.json"
    buildings_path = cell_dir / "raw" / "buildings.geojson"
    if not manifest_path.exists():
        raise ValueError("authoritative source manifest missing")
    if not buildings_path.exists():
        raise ValueError("authoritative buildings source missing")

    source = _read(manifest_path)
    buildings = _read(buildings_path)
    cell_id = cell_dir.name
    if source.get("cell_id") != cell_id:
        raise ValueError("source cell identity mismatch")
    if source.get("crs") != CRS:
        raise ValueError("source cell CRS mismatch")
    bbox = source.get("bbox")
    if not isinstance(bbox, list) or len(bbox) != 4 or not all(isinstance(v, (int, float)) for v in bbox):
        raise ValueError("source cell bbox missing or invalid")
    if not (bbox[0] < bbox[2] and bbox[1] < bbox[3]) or min(bbox) < 10_000:
        raise ValueError("source cell bbox does not look like EPSG:31370")
    if buildings.get("type") != "FeatureCollection":
        raise ValueError("authoritative buildings source is not a FeatureCollection")

    layers = source.get("layers") or {}
    building_layer = layers.get("buildings") if isinstance(layers, dict) else None
    if not isinstance(building_layer, dict):
        raise ValueError("source manifest does not prove the buildings layer")
    declared_count = building_layer.get("features")
    actual_count = len(buildings.get("features") or [])
    if declared_count != actual_count:
        raise ValueError(f"building feature count mismatch manifest={declared_count} source={actual_count}")

    invalid_ownership = int(building_layer.get("invalid_ownership_features", 0) or 0)
    authoritative_ready = invalid_ownership == 0
    uncertainties = [
        "runtime geometry not generated or validated",
        "collision quality not validated",
        "streaming behavior not validated",
        "terrain evidence not acquired",
        "building height evidence not acquired",
        "photo-match not evaluated for this cell",
        "streamed-cell performance not measured",
    ]
    if invalid_ownership:
        uncertainties.insert(0, "authoritative building source contains features with invalid canonical ownership")

    result = {
        "format": FORMAT,
        "cell_id": cell_id,
        "crs": CRS,
        "bbox": bbox,
        "maturity": {
            "state": "data_ready" if authoritative_ready else "quarantine",
            "gates": {gate: False for gate in GATES},
        },
        "provenance": {
            "source_records_present": True,
            "primary": "UrbIS WFS / Paradigm",
            "source_manifest_digest": _digest(source),
            "buildings_source_digest": _digest(buildings),
        },
        "geometry": {
            "authoritative_geometry_ready": authoritative_ready,
            "source_manifest": f"data/urbis/remaining_brussels/cells/{cell_id}/manifest.json",
            "layers": ["buildings"],
            "building_feature_count": actual_count,
        },
        "terrain": {"status": "evidence_pending"},
        "heights": {"status": "evidence_pending"},
        "collisions": {"status": "not_validated"},
        "streaming": {"status": "not_validated"},
        "photo_match": {"status": "not_evaluated", "open_major_mismatches": None},
        "performance": {"status": "not_measured_as_streamed_cell", "budget_pass": False},
        "uncertainties": uncertainties,
    }
    result["maturity_digest"] = _digest(result)
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cell-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = build(args.cell_dir)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        "BOOTSTRAP_CELL_MATURITY_OK",
        result["cell_id"],
        result["maturity"]["state"],
        result["geometry"]["building_feature_count"],
        result["maturity_digest"],
    )


if __name__ == "__main__":
    main()
