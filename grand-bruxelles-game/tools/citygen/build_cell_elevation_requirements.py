#!/usr/bin/env python3
"""Derive deterministic official DSM/DTM evidence requirements for one CityGen cell.

This stage never downloads a raster and never flips a maturity gate. It converts
an authoritative EPSG:31370 cell bbox into the minimal set of 1 km Paradigm
UrbIS 2021 DSM/DTM tiles that must later be resolved, downloaded, hashed and
validated before terrain or height evidence can be accepted.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

FORMAT = "grand-bruxelles-cell-elevation-requirements-v1"
CRS = "EPSG:31370"
DSM_DATASET_ID = "8c2d921e-6a53-11ed-bfb5-010101010000"
DTM_DATASET_ID = "1d7bd49d-fe83-4388-af85-6f5dc8ec7909"
BASE = "https://urbisdownload.datastore.brussels/atomfeed"


def _read(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def _digest(value: Any) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")).hexdigest()


def tile_codes_for_bbox(bbox: list[float | int]) -> list[str]:
    if len(bbox) != 4 or not all(isinstance(v, (int, float)) for v in bbox):
        raise ValueError("bbox must contain four numeric EPSG:31370 coordinates")
    min_e, min_n, max_e, max_n = [float(v) for v in bbox]
    if not (min_e < max_e and min_n < max_n) or min(bbox) < 10_000:
        raise ValueError("bbox does not look like EPSG:31370 metres")
    # Half-open max edge: a cell ending exactly on a kilometre boundary does not
    # request the adjacent tile.
    epsilon = 1e-6
    xs = range(int(min_e // 1000), int((max_e - epsilon) // 1000) + 1)
    ys = range(int(min_n // 1000), int((max_n - epsilon) // 1000) + 1)
    return [f"{x:03d}{y:03d}" for x in xs for y in ys]


def build(cell_dir: Path) -> dict[str, Any]:
    manifest_path = cell_dir / "manifest.json"
    maturity_path = cell_dir / "maturity.json"
    if not manifest_path.exists():
        raise ValueError("authoritative source manifest missing")
    if not maturity_path.exists():
        raise ValueError("maturity sidecar missing")
    source = _read(manifest_path)
    maturity = _read(maturity_path)
    cell_id = cell_dir.name
    if source.get("cell_id") != cell_id or maturity.get("cell_id") != cell_id:
        raise ValueError("cell identity mismatch")
    if source.get("crs") != CRS or maturity.get("crs") != CRS:
        raise ValueError("cell CRS mismatch")
    bbox = source.get("bbox")
    if bbox != maturity.get("bbox"):
        raise ValueError("source/maturity bbox mismatch")
    tiles = tile_codes_for_bbox(bbox)
    if not tiles:
        raise ValueError("cell has no elevation tiles")
    result = {
        "format": FORMAT,
        "cell_id": cell_id,
        "crs": CRS,
        "bbox": bbox,
        "expected_1km_tile_codes": tiles,
        "official_sources": {
            "dsm": {
                "name": "Paradigm UrbIS Digital Surface Model 2021",
                "dataset_id": DSM_DATASET_ID,
                "atom_feed": f"{BASE}/{DSM_DATASET_ID}-en.xml",
            },
            "dtm": {
                "name": "Paradigm UrbIS Digital Terrain Model 2021",
                "dataset_id": DTM_DATASET_ID,
                "atom_feed": f"{BASE}/{DTM_DATASET_ID}-en.xml",
            },
        },
        "required_validation": [
            "resolve_exact_official_archive_per_tile_and_kind",
            "download_from_official_https_host",
            "sha256_each_archive",
            "safe_extract_exactly_one_raster_per_tile",
            "validate_epsg31370_bounds_resolution_and_transform",
            "validate_dsm_dtm_pair_alignment",
            "derive_terrain_and_building_height_evidence",
        ],
        "maturity_effect": {
            "terrain_gate": False,
            "heights_gate": False,
            "reason": "requirements_only_no_raster_evidence_yet",
        },
    }
    result["requirements_digest"] = _digest(result)
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cell-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = build(args.cell_dir)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("CELL_ELEVATION_REQUIREMENTS_OK", result["cell_id"], result["expected_1km_tile_codes"], result["requirements_digest"])


if __name__ == "__main__":
    main()
