#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).parents[1]
CANDIDATE = ROOT / "data" / "city_machine" / "road_cell_coverage_candidates.json"
ADAPTER = ROOT / "tools" / "qa" / "measure_road_cell_municipality_preflight_v2.py"

EXPECTED_SCHEMA = "grand-bruxelles-road-cell-coverage-candidates-v2"
EXPECTED_CANDIDATE_SHA = "8aaca3178894950a8a1efe8235e3313f34d4d23656b968a9cbf87666284acd7b"
EXPECTED_ROAD_SOURCE_SHA = "899bc73ee0eea3623d7cc45455a542c1704039ef0239c13c33b3c74b4a241398"
EXPECTED_ROAD_SEMANTIC_SHA = "4ec4ba4ad46a999d3ea32ab4a42b6825d6e43f11fcae92ac9b7a4236222913e0"


def load_adapter():
    spec = importlib.util.spec_from_file_location("municipality_preflight_v2", ADAPTER)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_municipality_preflight_is_rebound_to_current_road_cell_v2() -> None:
    payload = json.loads(CANDIDATE.read_text(encoding="utf-8"))
    assert payload["schema"] == EXPECTED_SCHEMA
    assert payload["semantic_sha256"] == EXPECTED_CANDIDATE_SHA
    assert payload["road_source_sha256"] == EXPECTED_ROAD_SOURCE_SHA
    assert payload["road_semantic_sha256"] == EXPECTED_ROAD_SEMANTIC_SHA
    assert payload["candidate_cell_count"] == 8
    assert payload["status"] == "DISCOVERED_SOURCE_ONLY"

    m = load_adapter()
    assert m.EXPECTED_CANDIDATE_SEMANTIC_SHA256 == EXPECTED_CANDIDATE_SHA
    assert m.EXPECTED_ROAD_SOURCE_SHA256 == EXPECTED_ROAD_SOURCE_SHA
    assert m.EXPECTED_ROAD_SEMANTIC_SHA256 == EXPECTED_ROAD_SEMANTIC_SHA
    candidate = m.validate_candidate_v2(payload)
    assert candidate["grid_cell_id"] == "E148000_N170000"
    assert candidate["road_ids"] == [13842686, 684214770]
    assert candidate["point_hits"] == 9
    assert candidate["segment_hits"] == 7
    for key in (
        "registration_authorized",
        "road_cell_mapping_authorized",
        "runtime_mount_authorized",
        "rendered_geometry_authorized",
        "collision_authorized",
        "safe_spawn_authorized",
        "jouable_promotion_authorized",
    ):
        assert payload[key] is False
        assert candidate[key] is False
