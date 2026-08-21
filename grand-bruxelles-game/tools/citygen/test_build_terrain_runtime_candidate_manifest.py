#!/usr/bin/env python3
import copy
import importlib.util
import json
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("terrain_candidate", HERE / "build_terrain_runtime_candidate_manifest.py")
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)

CELL = "bxl-e142000-n167000-s500"


def seal(payload, field):
    payload = copy.deepcopy(payload)
    payload[field] = mod._digest(payload)
    return payload


def write(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


terrain = seal(
    {
        "format": mod.TERRAIN_LOD_FORMAT,
        "cell_id": CELL,
        "crs": mod.CRS,
        "bbox": [142000.0, 167000.0, 142500.0, 167500.0],
        "source": "official_validated_DTM",
        "source_raster_validation_digest": "1" * 64,
        "source_value_evidence_digest": "2" * 64,
        "source_pixel_size_m": 0.5,
        "selection": {
            "selected_resolution_m": 2.0,
            "selected_p95_abs_error_m": 0.11,
            "selected_vertex_count": 62500,
            "blockers": [],
            "runtime_approved": False,
        },
        "runtime_approved": False,
    },
    "evidence_digest",
)

secondary = seal(
    {
        "format": mod.SECONDARY_FORMAT,
        "cell_id": CELL,
        "crs": mod.CRS,
        "candidate_count": 2,
        "validated_candidate_count": 1,
        "blocked_candidate_count": 1,
        "secondary_validation_complete": False,
        "candidates": [
            {
                "building_id": "B-1",
                "candidate_height_m": 12.5,
                "secondary_status": "validated",
                "semantic_height_m": 12.46,
                "abs_delta_m": 0.04,
                "semantic_match_score": 0.98,
                "semantic_match_margin": 0.21,
                "runtime_approved": False,
            },
            {
                "building_id": "B-2",
                "candidate_height_m": 18.2,
                "secondary_status": "blocked_missing_secondary_evidence",
                "semantic_height_m": None,
                "abs_delta_m": None,
                "semantic_match_score": None,
                "semantic_match_margin": None,
                "runtime_approved": False,
            },
        ],
        "blockers": ["secondary_independent_height_validation_incomplete"],
        "runtime_promotion_allowed": False,
        "runtime_approved_count": 0,
    },
    "validation_digest",
)

with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    terrain_path = root / "terrain.json"
    secondary_path = root / "secondary.json"
    write(terrain_path, terrain)
    write(secondary_path, secondary)

    result = mod.build(terrain_path, secondary_path)
    assert result["cell_id"] == CELL
    assert result["terrain"]["selected_resolution_m"] == 2.0
    assert result["building_heights"]["mode"] == "secondary_validated_subset_only_no_fallback"
    assert result["building_heights"]["validated_count"] == 1
    assert result["building_heights"]["blocked_count"] == 1
    assert result["building_heights"]["contract_complete"] is False
    assert [row["building_id"] for row in result["building_heights"]["validated"]] == ["B-1"]
    assert result["building_heights"]["unvalidated_fallback_allowed"] is False
    assert "secondary_height_contract_incomplete" in result["blockers"]
    assert "height_contract" in result["remaining_runtime_gates"]
    assert result["terrain_runtime_authorized"] is False
    assert result["runtime_geometry_authorized"] is False
    assert result["collision_authorized"] is False
    assert result["navigation_authorized"] is False
    assert result["runtime_mount_authorized"] is False
    assert result["production_discovery_eligible"] is False
    assert result["automatic_production_mutation"] is False
    assert result["candidate_digest"] == mod._digest({k: v for k, v in result.items() if k != "candidate_digest"})

    complete = copy.deepcopy(secondary)
    complete.pop("validation_digest")
    complete["validated_candidate_count"] = 2
    complete["blocked_candidate_count"] = 0
    complete["secondary_validation_complete"] = True
    complete["candidates"][1]["secondary_status"] = "validated"
    complete["candidates"][1]["semantic_height_m"] = 18.18
    complete["candidates"][1]["abs_delta_m"] = 0.02
    complete["candidates"][1]["semantic_match_score"] = 0.97
    complete["candidates"][1]["semantic_match_margin"] = 0.19
    complete["blockers"] = []
    complete = seal(complete, "validation_digest")
    write(secondary_path, complete)
    complete_result = mod.build(terrain_path, secondary_path)
    assert complete_result["building_heights"]["contract_complete"] is True
    assert complete_result["building_heights"]["validated_count"] == 2
    assert "height_contract" not in complete_result["remaining_runtime_gates"]
    assert "terrain_mesh" in complete_result["remaining_runtime_gates"]
    assert complete_result["runtime_mount_authorized"] is False

    tampered = copy.deepcopy(terrain)
    tampered["source_pixel_size_m"] = 999.0
    write(terrain_path, tampered)
    try:
        mod.build(terrain_path, secondary_path)
        raise AssertionError("tampered terrain evidence digest must fail closed")
    except ValueError as exc:
        assert "does not match payload content" in str(exc)

    write(terrain_path, terrain)
    unsafe = copy.deepcopy(complete)
    unsafe.pop("validation_digest")
    unsafe["runtime_promotion_allowed"] = True
    unsafe = seal(unsafe, "validation_digest")
    write(secondary_path, unsafe)
    try:
        mod.build(terrain_path, secondary_path)
        raise AssertionError("runtime-authorized height input must fail closed")
    except ValueError as exc:
        assert "forbid runtime promotion" in str(exc)

    mismatch = copy.deepcopy(complete)
    mismatch.pop("validation_digest")
    mismatch["cell_id"] = "bxl-e142500-n167000-s500"
    mismatch = seal(mismatch, "validation_digest")
    write(secondary_path, mismatch)
    try:
        mod.build(terrain_path, secondary_path)
        raise AssertionError("cell mismatch must fail closed")
    except ValueError as exc:
        assert "cell identity mismatch" in str(exc)

print(
    "TERRAIN_RUNTIME_CANDIDATE_GUARDRAILS_OK",
    "validated_subset=true",
    "no_fallback=true",
    "digest_guard=true",
    "terrain_runtime=false",
    "collision=false",
    "production_discovery=false",
)
