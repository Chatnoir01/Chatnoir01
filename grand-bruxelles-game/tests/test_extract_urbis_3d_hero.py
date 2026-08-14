#!/usr/bin/env python3
"""Deterministic unit tests for the dependency-free UrbIS MultiPatch extractor."""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path


MODULE_PATH = Path(__file__).parents[1] / "tools" / "extract_urbis_3d_hero.py"
HERO_PATH = Path(__file__).parents[1] / "data" / "urbis" / "heroes" / "bourse_lod2.game.json"
SPEC = importlib.util.spec_from_file_location("extract_urbis_3d_hero", MODULE_PATH)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


def test_triangulates_closed_convex_ring() -> None:
    ring = [
        [0.0, 0.0, 5.0],
        [4.0, 0.0, 5.0],
        [4.0, 3.0, 5.0],
        [0.0, 3.0, 5.0],
        [0.0, 0.0, 5.0],
    ]
    triangles = MODULE.triangulate_ring(ring)
    assert len(triangles) == 2
    assert sorted({index for triangle in triangles for index in triangle}) == [0, 1, 2, 3]


def test_triangulates_concave_ring_without_fan_leak() -> None:
    ring = [
        [0.0, 0.0, 1.0],
        [4.0, 0.0, 1.0],
        [4.0, 4.0, 1.0],
        [2.0, 2.0, 1.0],
        [0.0, 4.0, 1.0],
    ]
    assert len(MODULE.triangulate_ring(ring)) == 3


def _triangle_area_xy(triangle: list[list[float]]) -> float:
    a, b, c = triangle
    return abs(
        (b[0] - a[0]) * (c[1] - a[1])
        - (b[1] - a[1]) * (c[0] - a[0])
    ) * 0.5


def test_multipatch_outer_ring_with_inner_ring_preserves_hole_area_and_source_vertices() -> None:
    outer = [
        [0.0, 0.0, 2.0],
        [10.0, 0.0, 2.0],
        [10.0, 10.0, 2.0],
        [0.0, 10.0, 2.0],
        [0.0, 0.0, 2.0],
    ]
    hole = [
        [3.0, 3.0, 2.0],
        [3.0, 7.0, 2.0],
        [7.0, 7.0, 2.0],
        [7.0, 3.0, 2.0],
        [3.0, 3.0, 2.0],
    ]
    patch = {
        "parts": [0, len(outer)],
        "part_types": [MODULE.PART_OUTER_RING, MODULE.PART_INNER_RING],
        "points": outer + hole,
    }

    triangles = MODULE.multipatch_triangles(patch)

    assert abs(sum(_triangle_area_xy(triangle) for triangle in triangles) - 84.0) <= 1.0e-8
    source_vertices = {tuple(point) for point in outer[:-1] + hole[:-1]}
    assert all(tuple(vertex) in source_vertices for triangle in triangles for vertex in triangle)
    for triangle in triangles:
        centroid_x = sum(vertex[0] for vertex in triangle) / 3.0
        centroid_y = sum(vertex[1] for vertex in triangle) / 3.0
        assert not (3.0 < centroid_x < 7.0 and 3.0 < centroid_y < 7.0)


def test_multipatch_triangle_strip_is_deterministic() -> None:
    patch = {
        "parts": [0],
        "part_types": [MODULE.PART_TRIANGLE_STRIP],
        "points": [
            [0.0, 0.0, 0.0],
            [0.0, 1.0, 0.0],
            [1.0, 0.0, 0.0],
            [1.0, 1.0, 0.0],
        ],
    }
    triangles = MODULE.multipatch_triangles(patch)
    assert triangles == [
        [patch["points"][0], patch["points"][1], patch["points"][2]],
        [patch["points"][2], patch["points"][1], patch["points"][3]],
    ]


def test_committed_bourse_source_contract() -> None:
    data = json.loads(HERO_PATH.read_text(encoding="utf-8"))
    source = data["source"]
    evidence = data["evidence"]
    assert data["schema"] == "grand-bruxelles-urbis-hero-mesh-v1"
    assert data["hero_id"] == "bourse"
    assert data["runtime_approved"] is False
    assert source["dataset_id"] == "e9ec2aa4-cffd-11ee-bccc-00090ffe0001"
    assert source["license"] == "CC0-1.0"
    assert source["crs"] == "EPSG:31370"
    assert source["building_2d_id"] == "https://databrussels.be/id/building/1751663"
    assert source["building_solid_id"] == "https://databrussels.be/id/buildingsolid/617669"
    assert source["package_sha256"] == "cf8449d1a62b0e47aafe6d715ff6a2739f5c48f6d75995f7f418305a5d6cf3d2"
    assert source["building_faces_shp_sha256"] == "5371b8dfc65bb0565677ccbbeb0936444d827daba81a7e508de3d5f530536997"
    assert source["building_solids_shp_sha256"] == "e11a1ddae370037f1495c7fa2d106245c70fc36a4c5c15c7eb48bd676900c0ec"
    assert evidence["face_count"] == 645
    assert evidence["face_type_counts"] == {
        "WALLSURFACE": 413,
        "ROOFSURFACE": 231,
        "GROUNDSURFACE": 1,
    }
    assert evidence["triangle_count"] == 1818
    assert evidence["multipatch_part_type_counts"] == {"4": 645}
    assert evidence["source_bbox_xy"] == [148665.846, 170800.642, 148752.922, 170876.851]
    assert evidence["source_z_min"] == 18.2459
    assert evidence["source_z_max"] == 58.4012
    assert evidence["height_m"] == 40.1553


if __name__ == "__main__":
    test_triangulates_closed_convex_ring()
    test_triangulates_concave_ring_without_fan_leak()
    test_multipatch_outer_ring_with_inner_ring_preserves_hole_area_and_source_vertices()
    test_multipatch_triangle_strip_is_deterministic()
    test_committed_bourse_source_contract()
    print("test_extract_urbis_3d_hero: PASS")
