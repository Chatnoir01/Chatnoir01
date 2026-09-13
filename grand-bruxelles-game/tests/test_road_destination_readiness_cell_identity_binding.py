#!/usr/bin/env python3
from __future__ import annotations

import copy
from pathlib import Path

import validate_road_destination_readiness_authorization as authorization

CATALOG = Path(__file__).resolve().parents[1] / "data/provenance/brussels_road_destination_readiness_catalog.json"


def _must_reject(catalog: dict[str, object], label: str) -> None:
    try:
        authorization.validate(catalog)
    except ValueError:
        return
    raise AssertionError(f"{label} mutation was accepted")


def main() -> int:
    catalog = authorization._load(CATALOG)
    authorization.validate(catalog)

    cell_id_drift = copy.deepcopy(catalog)
    cell_id_drift["destinations"][0]["cell_id"] = "bxl-e148500-n170500-s500"
    _must_reject(cell_id_drift, "cell_id/grid identity drift")

    grid_id_drift = copy.deepcopy(catalog)
    grid_id_drift["destinations"][0]["grid_cell_id"] = "E148500_N170500"
    _must_reject(grid_id_drift, "grid_cell_id drift")

    manifest_path_drift = copy.deepcopy(catalog)
    manifest_path_drift["destinations"][0]["cell_manifest_path"] = "data/cell_manifests/bxl-e148500-n170500-s500.json"
    _must_reject(manifest_path_drift, "cell manifest path drift")

    bbox_drift = copy.deepcopy(catalog)
    bbox_drift["destinations"][0]["cell_bbox"] = [147500.0, 169500.0, 148001.0, 170000.0]
    _must_reject(bbox_drift, "cell bbox drift")

    crs_drift = copy.deepcopy(catalog)
    crs_drift["destinations"][0]["cell_crs"] = "EPSG:4326"
    _must_reject(crs_drift, "cell CRS drift")

    print(
        "ROAD_DESTINATION_READINESS_CELL_IDENTITY_BINDING_OK "
        "cell_id_grid_bound=true manifest_path_bound=true bbox_bound=true crs_bound=true"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
