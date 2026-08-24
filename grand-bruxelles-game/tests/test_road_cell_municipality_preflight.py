#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

import pytest

MODULE_PATH = Path(__file__).parents[1] / "tools" / "qa" / "measure_road_cell_municipality_preflight.py"


def load_module():
    spec = importlib.util.spec_from_file_location("municipality_preflight", MODULE_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def feature(fid: str, name: str, coords: list[list[float]], inspire_id: str | None = None) -> dict:
    properties = {"NAMEFRE": name}
    if inspire_id is not None:
        properties.update({"INSPIRE_ID": inspire_id, "NISCODE": "21004"})
    return {
        "type": "Feature",
        "id": fid,
        "properties": properties,
        "geometry": {"type": "Polygon", "coordinates": [coords]},
    }


def test_single_official_municipality_cover_is_eligible() -> None:
    m = load_module()
    official_id = "https://databrussels.be/id/municipality/5000074"
    fc = {
        "type": "FeatureCollection",
        "features": [
            feature(
                "volatile-geoserver-fid",
                "Bruxelles",
                [[147900, 169900], [148600, 169900], [148600, 170600], [147900, 170600], [147900, 169900]],
                official_id,
            )
        ],
    }
    result = m.analyze_municipality_coverage([148000, 170000, 148500, 170500], fc)
    assert result["status"] == "MUNICIPALITY_PROVEN_SINGLE"
    assert result["municipality_id"] == official_id
    assert result["municipality_niscode"] == "21004"
    assert result["coverage_ratio"] == pytest.approx(1.0)
    assert result["registration_authorized"] is False


def test_boundary_cell_stays_hold() -> None:
    m = load_module()
    fc = {
        "type": "FeatureCollection",
        "features": [
            feature(
                "municipality.a",
                "A",
                [[148000, 170000], [148250, 170000], [148250, 170500], [148000, 170500], [148000, 170000]],
            ),
            feature(
                "municipality.b",
                "B",
                [[148250, 170000], [148500, 170000], [148500, 170500], [148250, 170500], [148250, 170000]],
            ),
        ],
    }
    result = m.analyze_municipality_coverage([148000, 170000, 148500, 170500], fc)
    assert result["status"] == "HOLD_MUNICIPALITY_BOUNDARY_CELL"
    assert len(result["intersections"]) == 2
    assert result["registration_authorized"] is False


def test_semantic_basis_ignores_transport_only_evidence() -> None:
    m = load_module()
    base = {
        "municipality_source": {"raw_payload_sha256": "raw-a", "crs": "EPSG:31370"},
        "municipality_coverage": {
            "transport_feature_ids": {"stable": "fid-a"},
            "municipality_id": "stable",
        },
        "semantic_sha256": "old",
    }
    changed = json.loads(json.dumps(base))
    changed["municipality_source"]["raw_payload_sha256"] = "raw-b"
    changed["municipality_coverage"]["transport_feature_ids"] = {"stable": "fid-b"}
    assert m._semantic_basis(base) == m._semantic_basis(changed)


def test_candidate_lock_requires_grand_place_and_closed_rails() -> None:
    m = load_module()
    payload = {
        "schema": "grand-bruxelles-road-cell-coverage-candidates-v1",
        "status": "DISCOVERED_SOURCE_ONLY",
        "semantic_sha256": m.EXPECTED_CANDIDATE_SEMANTIC_SHA256,
        "road_source_sha256": m.EXPECTED_ROAD_SOURCE_SHA256,
        "candidate_cell_count": 8,
        "registration_authorized": False,
        "road_cell_mapping_authorized": False,
        "runtime_mount_authorized": False,
        "rendered_geometry_authorized": False,
        "collision_authorized": False,
        "safe_spawn_authorized": False,
        "jouable_promotion_authorized": False,
        "candidates": [
            {
                "grid_cell_id": "E148000_N170000",
                "bbox": [148000.0, 170000.0, 148500.0, 170500.0],
                "corridor_anchor_ids": ["grand_place"],
                "road_count": 2,
                "road_ids": [13842686, 684214770],
                "point_hits": 9,
                "segment_hits": 7,
                "registration_authorized": False,
                "road_cell_mapping_authorized": False,
                "runtime_mount_authorized": False,
                "rendered_geometry_authorized": False,
                "collision_authorized": False,
                "safe_spawn_authorized": False,
                "jouable_promotion_authorized": False,
            }
        ],
    }
    candidate = m.validate_candidate_lock(payload)
    assert candidate["grid_cell_id"] == "E148000_N170000"

    bad = json.loads(json.dumps(payload))
    bad["candidates"][0]["runtime_mount_authorized"] = True
    with pytest.raises(RuntimeError, match="authorization"):
        m.validate_candidate_lock(bad)
