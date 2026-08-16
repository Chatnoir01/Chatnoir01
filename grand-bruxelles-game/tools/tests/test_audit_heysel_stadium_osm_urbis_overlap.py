#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
from pathlib import Path

from shapely.geometry import Polygon, mapping

SCRIPT_PATH = Path(__file__).resolve().parents[1] / "audit_heysel_stadium_osm_urbis_overlap.py"
spec = importlib.util.spec_from_file_location("heysel_overlap", SCRIPT_PATH)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)


def main() -> None:
    stadium = Polygon([(0.0, 0.0), (100.0, 0.0), (100.0, 50.0), (0.0, 50.0)])
    inside = Polygon([(10.0, 10.0), (40.0, 10.0), (40.0, 30.0), (10.0, 30.0)])
    partial = Polygon([(90.0, 10.0), (120.0, 10.0), (120.0, 30.0), (90.0, 30.0)])
    outside = Polygon([(150.0, 0.0), (170.0, 0.0), (170.0, 20.0), (150.0, 20.0)])
    collection = {
        "type": "FeatureCollection",
        "features": [
            {
                "type": "Feature",
                "id": "inside",
                "properties": {"INSPIRE_ID": "inside-id", "BLOCK_ID": "block-a"},
                "geometry": mapping(inside),
            },
            {
                "type": "Feature",
                "id": "partial",
                "properties": {"INSPIRE_ID": "partial-id", "BLOCK_ID": "block-a"},
                "geometry": mapping(partial),
            },
            {
                "type": "Feature",
                "id": "outside",
                "properties": {},
                "geometry": mapping(outside),
            },
        ],
    }
    audit = module.build_overlap_audit(collection, stadium, {"way_id": module.OSM_WAY_ID})
    assert audit["status"] == "osm_semantic_envelope_vs_urbis_geometry_evidence_only"
    assert audit["intersecting_urbis_feature_count"] == 2
    assert audit["intersecting_urbis_features"][0]["feature_id"] == "inside"
    assert abs(audit["intersecting_urbis_features"][0]["intersection_area_m2"] - 600.0) < 0.001
    assert abs(audit["intersecting_urbis_features"][1]["intersection_area_m2"] - 200.0) < 0.001
    assert abs(audit["clipped_urbis_union_coverage_ratio"] - 0.16) < 0.000001
    assert "OSM supplies only the semantic stadium envelope" in audit["decision_rule"]
    print("HEYSEL_OSM_URBIS_OVERLAP_UNIT_OK")


if __name__ == "__main__":
    main()
