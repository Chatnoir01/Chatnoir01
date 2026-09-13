#!/usr/bin/env python3
from __future__ import annotations

import copy
from pathlib import Path

from validate_road_destination_readiness_source_geometry_summary import _load, validate

ROOT = Path(__file__).resolve().parents[1]
CATALOG_PATH = ROOT / "data/provenance/brussels_road_destination_readiness_catalog.json"


def _must_reject(label: str, candidate: dict) -> None:
    try:
        validate(candidate, root=ROOT)
    except ValueError:
        return
    raise AssertionError(f"{label} mutation was accepted")


def main() -> int:
    catalog = _load(CATALOG_PATH)
    validate(catalog, root=ROOT)

    stale_count = copy.deepcopy(catalog)
    stale_count["destinations"][0]["source_local_point_count"] += 1
    _must_reject("source local point count drift", stale_count)

    boolean_count = copy.deepcopy(catalog)
    boolean_count["destinations"][0]["source_local_point_count"] = True
    _must_reject("boolean source local point count", boolean_count)

    bbox_min_drift = copy.deepcopy(catalog)
    bbox_min_drift["destinations"][0]["source_local_bbox"][0] -= 1.0
    _must_reject("source local bbox minimum drift", bbox_min_drift)

    bbox_max_drift = copy.deepcopy(catalog)
    bbox_max_drift["destinations"][0]["source_local_bbox"][3] += 1.0
    _must_reject("source local bbox maximum drift", bbox_max_drift)

    malformed_bbox = copy.deepcopy(catalog)
    malformed_bbox["destinations"][0]["source_local_bbox"] = [0.0, 0.0, 1.0]
    _must_reject("malformed source local bbox", malformed_bbox)

    print(
        "ROAD_DESTINATION_READINESS_SOURCE_GEOMETRY_SUMMARY_BINDING_OK "
        "source_local_point_count_bound=true source_local_bbox_bound=true "
        "finite_source_geometry_summary_required=true source_geometry_summary_fail_closed=true"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
