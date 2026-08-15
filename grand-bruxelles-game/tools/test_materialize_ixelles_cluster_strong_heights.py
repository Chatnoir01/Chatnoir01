#!/usr/bin/env python3
"""Synthetic regression for conservative multi-cell Ixelles height materialization."""
from __future__ import annotations

import importlib.util
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("materialize_ixelles_cluster_strong_heights.py")
spec = importlib.util.spec_from_file_location("cluster_strong_heights", MODULE_PATH)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

CELL = "bxl-e149500-n169000-s500"


def semantic_match(building: str, solid: str, height: float, score: float = 0.99, margin: float = 0.99) -> dict:
    return {
        "busolid_id": solid,
        "status": "matched_semantic_evidence",
        "matched_inspire_id": building,
        "match_score": score,
        "match_margin": margin,
        "semantic_height_m": height,
        "runtime_approved": False,
    }


def dsm(confidence: str, p50: float, p75: float, p90: float) -> dict:
    return {
        "confidence": confidence,
        "height_p50_m": str(p50),
        "height_p75_m": str(p75),
        "height_p90_m": str(p90),
    }


def runtime_cell(ids: list[str]) -> dict:
    return {
        "cell_id": CELL,
        "source_bbox": [149500.0, 169000.0, 150000.0, 169500.0],
        "coordinate_system": {"coordinates_are_current_game_world": True},
        "accuracy": {"plan_geometry": "official_urbis", "building_heights": "temporary_area_heuristic_pending_urbis_landscape_or_lidar"},
        "buildings": [{"id": identity} for identity in ids],
    }


def main() -> int:
    a = "https://databrussels.be/id/building/A"
    b = "https://databrussels.be/id/building/B"
    c = "https://databrussels.be/id/building/C"
    d = "https://databrussels.be/id/building/D"
    e = "https://databrussels.be/id/building/E"
    semantic = {
        "cell": CELL,
        "policy": {"crs": "EPSG:31370", "runtime_approval": False},
        "matches": [
            semantic_match(a, "solid-a-best", 12.0, score=0.99, margin=0.99),
            semantic_match(a, "solid-a-tighter-delta", 12.4, score=0.95, margin=0.95),
            semantic_match(b, "solid-b-medium", 10.0),
            semantic_match(c, "solid-c-conflict", 10.0),
            semantic_match(d, "solid-d-weak", 10.0, score=0.85, margin=0.30),
            semantic_match(e, "solid-e-outside", 15.0),
        ],
    }
    dsm_rows = {
        a: dsm("high", 11.5, 12.5, 13.0),
        b: dsm("medium", 10.5, 11.0, 12.0),
        c: dsm("high", 18.0, 20.0, 22.0),
        d: dsm("high", 10.2, 11.0, 11.8),
        e: dsm("high", 14.5, 15.5, 16.0),
    }
    result = module.materialize_contract(semantic, dsm_rows, runtime_cell([a, b, c, d]), cell_id=CELL)

    assert result["cell_id"] == CELL
    assert result["bbox_epsg31370"] == [149500.0, 169000.0, 150000.0, 169500.0]
    assert result["runtime_footprint_count"] == 4
    assert result["eligible_count"] == 1
    assert result["duplicate_strong_records_removed"] == 1
    assert result["strong_candidates_before_runtime_intersection"] == 3
    assert result["strong_candidates_outside_runtime"] == 1
    assert result["runtime_approved"] is False
    assert result["policy"]["required_dsm_confidence"] == "high"
    assert result["policy"]["max_abs_delta_m"] == 2.0
    assert result["policy"]["min_semantic_match_score"] == 0.90
    assert result["policy"]["min_semantic_match_margin"] == 0.25

    record = result["records"][0]
    assert record["building_id"] == a
    assert record["busolid_id"] == "solid-a-best"
    assert record["semantic_height_m"] == 12.0
    assert record["abs_delta_m"] == 0.5
    assert record["visual_runtime_eligible"] is True
    assert record["runtime_approved"] is False
    assert len({r["building_id"] for r in result["records"]}) == result["eligible_count"]

    try:
        module.materialize_contract(semantic, dsm_rows, runtime_cell([a]), cell_id="wrong-cell")
    except ValueError as exc:
        assert "runtime cell id mismatch" in str(exc)
    else:
        raise AssertionError("cell mismatch must fail closed")

    print("IXELLES_CLUSTER_STRONG_HEIGHTS_TEST_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())