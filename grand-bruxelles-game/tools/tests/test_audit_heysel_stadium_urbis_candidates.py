#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
from pathlib import Path

SCRIPT_PATH = Path(__file__).resolve().parents[1] / "audit_heysel_stadium_urbis_candidates.py"
spec = importlib.util.spec_from_file_location("heysel_audit", SCRIPT_PATH)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)


def _square(cx: float, cy: float, half: float) -> list[list[float]]:
    return [
        [cx - half, cy - half],
        [cx + half, cy - half],
        [cx + half, cy + half],
        [cx - half, cy + half],
        [cx - half, cy - half],
    ]


def main() -> None:
    selector_e = float(module.SELECTOR["easting"])
    selector_n = float(module.SELECTOR["northing"])
    feature_collection = {
        "type": "FeatureCollection",
        "features": [
            {
                "type": "Feature",
                "id": "near-large",
                "properties": {"source": "synthetic"},
                "geometry": {
                    "type": "Polygon",
                    "coordinates": [_square(selector_e + 30.0, selector_n, 15.0)],
                },
            },
            {
                "type": "Feature",
                "id": "near-small",
                "properties": {},
                "geometry": {
                    "type": "Polygon",
                    "coordinates": [_square(selector_e + 10.0, selector_n, 3.0)],
                },
            },
            {
                "type": "Feature",
                "id": "far-large",
                "properties": {},
                "geometry": {
                    "type": "Polygon",
                    "coordinates": [_square(selector_e + 500.0, selector_n, 20.0)],
                },
            },
        ],
    }
    audit = module.build_audit(feature_collection, radius_m=100.0, min_area_m2=350.0)
    assert audit["status"] == "candidate_geometry_audit_only_no_final_selection"
    assert audit["candidate_count"] == 1
    candidate = audit["candidates"][0]
    assert candidate["feature_id"] == "near-large"
    assert abs(candidate["area_m2"] - 900.0) < 0.001
    assert abs(candidate["distance_to_selector_m"] - 30.0) < 0.001
    assert "Do not select a final stadium target" in audit["decision_rule"]

    metrics = module.geometry_metrics(
        {
            "type": "MultiPolygon",
            "coordinates": [
                [_square(100.0, 100.0, 5.0)],
                [_square(120.0, 100.0, 5.0)],
            ],
        }
    )
    assert metrics is not None
    assert abs(float(metrics["area_m2"]) - 200.0) < 0.001
    assert abs(float(metrics["centroid_easting"]) - 110.0) < 0.001
    print("HEYSEL_STADIUM_URBIS_AUDIT_UNIT_OK")


if __name__ == "__main__":
    main()
