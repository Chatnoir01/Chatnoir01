import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "data/source_plans/brussels_spatial_crosswalk_origin_evidence.lock.json"
PRECONDITION = ROOT / "data/source_plans/brussels_spatial_crosswalk_precondition.lock.json"
MIDI_CANDIDATE = ROOT / "data/qa/city_machine/midi_onboarding_candidate.json"
REGISTERED_INDEX = ROOT / "data/provenance/brussels_registered_cell_manifest_index.json"
RUNTIME_INDEX = ROOT / "data/runtime/road_destination_runtime_index.json"
LOWER_HEX_40 = re.compile(r"^[0-9a-f]{40}$")
SHA256_DIGEST = re.compile(r"^sha256:[0-9a-f]{64}$")
LOWER_HEX_64 = re.compile(r"^[0-9a-f]{64}$")

EXPECTED_TOP_LEVEL_KEYS = {"schema", "source_owner", "measured_contract", "authorization", "scope_note"}
EXPECTED_SOURCE_OWNER_KEYS = {
    "pr",
    "head_sha",
    "workflow",
    "run_id",
    "artifact_id",
    "artifact_digest",
    "artifact_name",
}
EXPECTED_MEASURED_CONTRACT_KEYS = {
    "schema",
    "cell_crs",
    "frame",
    "registered_cell_index",
    "registered_cell_index_semantic_sha256",
    "road_runtime_index",
    "road_runtime_catalog_sha256",
    "road_source",
    "road_source_sha256",
    "road_source_provider",
    "road_source_license",
    "raw_road_count",
    "road_count",
    "registered_cell_count",
    "overlapping_road_count",
    "semantic_sha256",
}
EXPECTED_FRAME_KEYS = {"crs", "origin_easting_m", "origin_northing_m", "formula"}
EXPECTED_AUTHORIZATION_KEYS = {
    "crosswalk_authorized",
    "road_cell_mapping_authorized",
    "runtime_mount_authorized",
    "rendered_geometry_authorized",
    "collision_authorized",
    "safe_spawn_authorized",
    "jouable_promotion_authorized",
}


def _assert_exact_keys(payload, expected, label):
    assert isinstance(payload, dict), f"{label} must be an object"
    assert set(payload) == expected, f"{label} schema drift: {set(payload) ^ expected}"


def test_spatial_crosswalk_origin_evidence_is_pinned_and_fail_closed():
    evidence = json.loads(EVIDENCE.read_text(encoding="utf-8"))
    precondition = json.loads(PRECONDITION.read_text(encoding="utf-8"))
    midi = json.loads(MIDI_CANDIDATE.read_text(encoding="utf-8"))

    _assert_exact_keys(evidence, EXPECTED_TOP_LEVEL_KEYS, "origin evidence")
    assert evidence["schema"] == "grand-bruxelles-spatial-crosswalk-origin-evidence-v1"
    assert isinstance(evidence["scope_note"], str) and evidence["scope_note"].strip() == evidence["scope_note"]
    assert evidence["scope_note"]

    owner = evidence["source_owner"]
    _assert_exact_keys(owner, EXPECTED_SOURCE_OWNER_KEYS, "source owner")
    assert owner == {
        "pr": 1562,
        "head_sha": "9fdbf01073deb311097bcc70e2e8b627a004a8b1",
        "workflow": "Grand Bruxelles City Machine Midi Runtime-Index Frame",
        "run_id": 34248313500,
        "artifact_id": 10065069360,
        "artifact_digest": "sha256:7c6dbd4e1ce3feeca476d60acfb147f97dd4cd43a0bc1063ca2d12059a230894",
        "artifact_name": "road-registered-cell-overlap-v2-candidate",
    }
    assert LOWER_HEX_40.fullmatch(owner["head_sha"])
    assert SHA256_DIGEST.fullmatch(owner["artifact_digest"])
    assert type(owner["pr"]) is int and owner["pr"] > 0
    assert type(owner["run_id"]) is int and owner["run_id"] > 0
    assert type(owner["artifact_id"]) is int and owner["artifact_id"] > 0

    measured = evidence["measured_contract"]
    _assert_exact_keys(measured, EXPECTED_MEASURED_CONTRACT_KEYS, "measured contract")
    assert measured["schema"] == "grand-bruxelles-road-registered-cell-overlap-measurement-v2"
    assert measured["cell_crs"] == "EPSG:31370"
    _assert_exact_keys(measured["frame"], EXPECTED_FRAME_KEYS, "measured frame")
    assert measured["frame"] == {
        "crs": "EPSG:31370",
        "origin_easting_m": 147868.29422791934,
        "origin_northing_m": 169538.62414926197,
        "formula": "E=origin_easting_m+x;N=origin_northing_m-z",
    }
    assert measured["registered_cell_index"] == "data/provenance/brussels_registered_cell_manifest_index.json"
    assert measured["road_runtime_index"] == "data/runtime/road_destination_runtime_index.json"
    assert REGISTERED_INDEX.is_file()
    assert RUNTIME_INDEX.is_file()
    for key in (
        "registered_cell_index_semantic_sha256",
        "road_runtime_catalog_sha256",
        "road_source_sha256",
        "semantic_sha256",
    ):
        assert isinstance(measured[key], str) and LOWER_HEX_64.fullmatch(measured[key]), f"invalid {key}"
    for key in ("raw_road_count", "road_count", "registered_cell_count", "overlapping_road_count"):
        assert type(measured[key]) is int and measured[key] >= 0, f"invalid {key}"
    assert measured["raw_road_count"] == 140
    assert measured["road_count"] == 139
    assert measured["registered_cell_count"] == 5
    assert measured["overlapping_road_count"] == 64
    assert measured["overlapping_road_count"] <= measured["road_count"] <= measured["raw_road_count"]

    candidate_contract = midi["coordinate_contract"]
    bridge = midi["road_frame_bridge"]
    assert candidate_contract["origin_easting_m"] == measured["frame"]["origin_easting_m"]
    assert candidate_contract["origin_northing_m"] == measured["frame"]["origin_northing_m"]
    assert bridge["lambert72_formula"] == measured["frame"]["formula"]
    assert bridge["road_runtime_index"] == measured["road_runtime_index"]
    assert bridge["road_runtime_catalog_sha256"] == measured["road_runtime_catalog_sha256"]
    assert bridge["road_source"] == measured["road_source"]
    assert bridge["road_source_sha256"] == measured["road_source_sha256"]
    assert bridge["road_source_provider"] == measured["road_source_provider"]
    assert bridge["road_source_license"] == measured["road_source_license"]

    assert precondition["crosswalk"]["status"] == "UNRESOLVED_PROVENANCE"
    assert precondition["crosswalk"]["authorized"] is False
    assert all(value is None for key, value in precondition["crosswalk"].items() if key in {
        "target_grid_contract", "target_crs", "transform_source", "transform_revision", "transform_license", "transform_sha256"
    })

    authorization = evidence["authorization"]
    _assert_exact_keys(authorization, EXPECTED_AUTHORIZATION_KEYS, "origin evidence authorization")
    assert authorization and all(type(value) is bool and value is False for value in authorization.values())
