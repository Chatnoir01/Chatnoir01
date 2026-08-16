#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("measure_osm_environment_coverage", ROOT / "measure_osm_environment_coverage.py")
assert SPEC and SPEC.loader
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)


def test_measure_selects_corridor_points_and_winner() -> None:
    runtime = {
        "origin": {"lat": 50.8419, "lon": 4.3480},
        "corridor": {"anchors": [{"x": 0.0, "z": 0.0}, {"x": 100.0, "z": 0.0}]},
    }
    raw = {
        "elements": [
            {"type": "node", "id": 1, "lat": 50.8419, "lon": 4.3480, "tags": {"natural": "tree"}},
            {"type": "node", "id": 2, "lat": 50.8419, "lon": 4.3481, "tags": {"natural": "tree"}},
            {"type": "node", "id": 3, "lat": 50.8419, "lon": 4.3482, "tags": {"highway": "street_lamp"}},
            {"type": "node", "id": 4, "lat": 50.8500, "lon": 4.3600, "tags": {"barrier": "bollard"}},
            {"type": "node", "id": 5, "lat": 50.8419, "lon": 4.3480, "tags": {"amenity": "bench"}},
        ]
    }
    result = mod.measure(raw, runtime, radius_m=25.0)
    assert result["counts"] == {"tree": 2, "street_lamp": 1, "bollard": 0}
    assert result["total"] == 3
    assert result["winner"] == "tree"
    assert result["tie"] == []
    assert result["source"] == "OpenStreetMap contributors via Overpass API"
    assert result["license"] == "ODbL-1.0"


def test_point_query_is_fail_closed_to_three_supported_classes() -> None:
    query = mod.build_point_query(mod.DEFAULT_BBOX)
    assert query.count("node[") == 3
    assert 'node["natural"="tree"]' in query
    assert 'node["highway"="street_lamp"]' in query
    assert 'node["barrier"="bollard"]' in query
    assert "bench" not in query


if __name__ == "__main__":
    test_measure_selects_corridor_points_and_winner()
    test_point_query_is_fail_closed_to_three_supported_classes()
    print("OSM_ENVIRONMENT_COVERAGE_TEST_OK")
