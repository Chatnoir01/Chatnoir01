import json
from pathlib import Path

import pytest

from tools.city_machine import validate_spatial_crosswalk_origin_artifact_receipt as validator

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "data/source_plans/brussels_spatial_crosswalk_origin_evidence.lock.json"
RECEIPT = ROOT / "data/source_plans/brussels_spatial_crosswalk_origin_artifact_receipt.lock.json"

EXPECTED_RECEIPT_KEYS = {"schema", "repository", "workflow_run", "artifact", "authorization", "scope_note"}
EXPECTED_RUN_KEYS = {"id", "head_sha"}
EXPECTED_ARTIFACT_KEYS = {"id", "name", "size_in_bytes", "digest"}
EXPECTED_AUTHORIZATION_KEYS = {
    "crosswalk_authorized",
    "road_cell_mapping_authorized",
    "runtime_mount_authorized",
    "rendered_geometry_authorized",
    "collision_authorized",
    "safe_spawn_authorized",
    "jouable_promotion_authorized",
}


def _reject_duplicate_pairs(pairs):
    payload = {}
    for key, value in pairs:
        if key in payload:
            raise ValueError(f"duplicate JSON key: {key}")
        payload[key] = value
    return payload


def _load_json_strict(path):
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=_reject_duplicate_pairs)


def _load_json_bytes_strict(raw):
    return json.loads(raw.decode("utf-8"), object_pairs_hook=_reject_duplicate_pairs)


def _exact_keys(payload, expected, label):
    assert isinstance(payload, dict), f"{label} must be an object"
    assert set(payload) == expected, f"{label} schema drift: {set(payload) ^ expected}"


def test_production_validator_exposes_origin_artifact_receipt_binding():
    assert callable(validator.validate_origin_artifact_receipt)
    validator.validate_origin_artifact_receipt(EVIDENCE.read_bytes(), RECEIPT.read_bytes())


def test_production_validator_rejects_duplicate_receipt_key():
    canonical = RECEIPT.read_bytes()
    duplicate = canonical.replace(
        b'{\n  "schema": "grand-bruxelles-spatial-crosswalk-origin-artifact-receipt-v1",',
        b'{\n  "schema": "grand-bruxelles-spatial-crosswalk-origin-artifact-receipt-v1",\n  "schema": "grand-bruxelles-spatial-crosswalk-origin-artifact-receipt-v1",',
        1,
    )
    assert duplicate != canonical
    with pytest.raises(ValueError, match="duplicate JSON key: schema"):
        validator.validate_origin_artifact_receipt(EVIDENCE.read_bytes(), duplicate)


def test_production_validator_rejects_repinned_owner_mismatch():
    evidence = json.loads(EVIDENCE.read_text(encoding="utf-8"))
    evidence["source_owner"]["artifact_id"] = 10065069361
    forged = (json.dumps(evidence, separators=(",", ":")) + "\n").encode("utf-8")
    with pytest.raises(ValueError, match="source_owner immutable identity drift"):
        validator.validate_origin_artifact_receipt(forged, RECEIPT.read_bytes())


def test_production_validator_rejects_open_authorization():
    receipt = json.loads(RECEIPT.read_text(encoding="utf-8"))
    receipt["authorization"]["runtime_mount_authorized"] = True
    forged = (json.dumps(receipt, separators=(",", ":")) + "\n").encode("utf-8")
    with pytest.raises(ValueError, match="runtime_mount_authorized must remain false"):
        validator.validate_origin_artifact_receipt(EVIDENCE.read_bytes(), forged)


def test_origin_artifact_receipt_duplicate_keys_fail_closed():
    canonical = RECEIPT.read_bytes()
    duplicate = canonical.replace(
        b'{\n  "schema": "grand-bruxelles-spatial-crosswalk-origin-artifact-receipt-v1",',
        b'{\n  "schema": "grand-bruxelles-spatial-crosswalk-origin-artifact-receipt-v1",\n  "schema": "grand-bruxelles-spatial-crosswalk-origin-artifact-receipt-v1",',
        1,
    )
    assert duplicate != canonical
    with pytest.raises(ValueError, match="duplicate JSON key: schema"):
        _load_json_bytes_strict(duplicate)


def test_origin_artifact_receipt_matches_locked_crosswalk_evidence():
    evidence = _load_json_strict(EVIDENCE)
    receipt = _load_json_strict(RECEIPT)

    _exact_keys(receipt, EXPECTED_RECEIPT_KEYS, "artifact receipt")
    assert receipt["schema"] == "grand-bruxelles-spatial-crosswalk-origin-artifact-receipt-v1"
    assert receipt["repository"] == "Chatnoir01/Chatnoir01"

    run = receipt["workflow_run"]
    artifact = receipt["artifact"]
    authorization = receipt["authorization"]
    owner = evidence["source_owner"]

    _exact_keys(run, EXPECTED_RUN_KEYS, "workflow run")
    _exact_keys(artifact, EXPECTED_ARTIFACT_KEYS, "artifact")
    _exact_keys(authorization, EXPECTED_AUTHORIZATION_KEYS, "artifact receipt authorization")

    assert run == {"id": 34248313500, "head_sha": "9fdbf01073deb311097bcc70e2e8b627a004a8b1"}
    assert artifact == {
        "id": 10065069360,
        "name": "road-registered-cell-overlap-v2-candidate",
        "size_in_bytes": 2473,
        "digest": "sha256:7c6dbd4e1ce3feeca476d60acfb147f97dd4cd43a0bc1063ca2d12059a230894",
    }

    assert owner["run_id"] == run["id"]
    assert owner["head_sha"] == run["head_sha"]
    assert owner["artifact_id"] == artifact["id"]
    assert owner["artifact_name"] == artifact["name"]
    assert owner["artifact_digest"] == artifact["digest"]

    assert authorization and all(type(value) is bool and value is False for value in authorization.values())
    assert isinstance(receipt["scope_note"], str) and receipt["scope_note"].strip() == receipt["scope_note"]
    assert receipt["scope_note"]