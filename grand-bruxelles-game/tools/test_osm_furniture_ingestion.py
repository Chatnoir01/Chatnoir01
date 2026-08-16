#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


fetch_osm = load_module("fetch_osm_slice", ROOT / "fetch_osm_slice.py")
transform = load_module("transform_osm_to_game", ROOT / "transform_osm_to_game.py")
runtime_slice = load_module("make_runtime_slice", ROOT / "make_runtime_slice.py")


def test_query_requests_only_supported_environment_points() -> None:
    query = fetch_osm.build_query(fetch_osm.DEFAULT_BBOX)
    assert 'node["natural"="tree"]' in query
    assert 'node["highway"="street_lamp"]' in query
    assert 'node["barrier"="bollard"]' in query


def test_converter_preserves_exact_supported_point_semantics() -> None:
    raw = {
        "elements": [
            {"type": "node", "id": 101, "lat": 50.8419, "lon": 4.3480, "tags": {"natural": "tree"}},
            {"type": "node", "id": 102, "lat": 50.8420, "lon": 4.3481, "tags": {"highway": "street_lamp"}},
            {"type": "node", "id": 103, "lat": 50.8421, "lon": 4.3482, "tags": {"barrier": "bollard"}},
            {"type": "node", "id": 104, "lat": 50.8422, "lon": 4.3483, "tags": {"amenity": "bench"}},
        ]
    }
    converted = transform.convert(raw, transform.DEFAULT_ORIGIN)
    points = converted["environment_points"]
    assert converted["stats"]["environment_points"] == 3
    assert [point["kind"] for point in points] == ["bollard", "street_lamp", "tree"]
    assert [point["osm_id"] for point in points] == [103, 102, 101]
    assert points[2]["position"] == [0.0, -0.0]
    assert all(set(point) == {"osm_id", "kind", "position"} for point in points)
    assert converted["source"] == "OpenStreetMap contributors via Overpass API"
    assert converted["license"] == "ODbL-1.0"


def test_runtime_slice_keeps_only_supported_corridor_points() -> None:
    source = [
        {"osm_id": 1, "kind": "tree", "position": [5.0, 2.0]},
        {"osm_id": 2, "kind": "street_lamp", "position": [25.0, 8.0]},
        {"osm_id": 3, "kind": "bollard", "position": [55.0, 3.0]},
        {"osm_id": 4, "kind": "bench", "position": [5.0, 1.0]},
        {"osm_id": 5, "kind": "tree", "position": [5.0, 80.0]},
    ]
    selected = runtime_slice.select_environment_points(
        source,
        [(0.0, 0.0), (60.0, 0.0)],
        radius=10.0,
        max_points=10,
    )
    assert [point["osm_id"] for point in selected] == [1, 3, 2]
    assert all(point["kind"] in {"tree", "street_lamp", "bollard"} for point in selected)
    assert runtime_slice.selected_bounds(selected) == [5.0, 2.0, 55.0, 8.0]


if __name__ == "__main__":
    test_query_requests_only_supported_environment_points()
    test_converter_preserves_exact_supported_point_semantics()
    test_runtime_slice_keeps_only_supported_corridor_points()
    print("OSM_FURNITURE_INGESTION_OK: tree/street_lamp/bollard nodes are queried, projected and carried into the playable corridor contract")
