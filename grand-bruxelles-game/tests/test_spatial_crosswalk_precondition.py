from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path

import pytest

from tools.city_machine.validate_spatial_crosswalk_precondition import (
    _load_json_no_duplicate_keys,
    validate_crosswalk_precondition,
)

ROOT = Path(__file__).resolve().parents[1]
MEASUREMENTS = ROOT / "data/source_plans/brussels_locked_road_source_measurements.lock.json"
PRECONDITION = ROOT / "data/source_plans/brussels_spatial_crosswalk_precondition.lock.json"

EXPECTED_MEASUREMENTS_PATH = "data/source_plans/brussels_locked_road_source_measurements.lock.json"
EXPECTED_EVIDENCE_GIT_BLOB_SHA1 = "785688868931d48845f1df47837feff7861399d7"
EXPECTED_SOURCE_FRAME = {
    "origin_lat": 50.8419,
    "origin_lon": 4.348,
    "axes": "X=east, Y=up, Z=south",
    "units": "metres",
}
EXPECTED_REQUIRED_PROVENANCE = [
    "target_grid_contract",
    "target_crs",
    "transform_source",
    "transform_revision",
    "transform_license",
    "transform_sha256",
]


def _git_blob_sha1(raw: bytes) -> str:
    return hashlib.sha1(f"blob {len(raw)}\0".encode("ascii") + raw).hexdigest()


def _load() -> tuple[bytes, dict, dict]:
    measurements_raw = MEASUREMENTS.read_bytes()
    return (
        measurements_raw,
        json.loads(measurements_raw.decode("utf-8")),
        json.loads(PRECONDITION.read_text(encoding="utf-8")),
    )


def _validate_measurement_candidate(candidate_measurements: dict, payload: dict) -> None:
    candidate_raw = (json.dumps(candidate_measurements, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")
    candidate_payload = copy.deepcopy(payload)
    candidate_payload["source_measurement_manifest"]["git_blob_sha1"] = _git_blob_sha1(candidate_raw)
    validate_crosswalk_precondition(candidate_payload, candidate_raw)


def test_spatial_crosswalk_precondition_is_locked_and_fail_closed() -> None:
    assert MEASUREMENTS.is_file(), "locked road-source measurements are required"
    assert PRECONDITION.is_file(), "spatial crosswalk precondition lock is required"

    measurements_raw, measurements, payload = _load()

    assert payload == {
        "schema": "grand-bruxelles-spatial-crosswalk-precondition-v1",
        "source_measurement_manifest": {
            "path": EXPECTED_MEASUREMENTS_PATH,
            "git_blob_sha1": _git_blob_sha1(measurements_raw),
            "source_evidence_git_blob_sha1": EXPECTED_EVIDENCE_GIT_BLOB_SHA1,
            "source_frame": EXPECTED_SOURCE_FRAME,
        },
        "crosswalk": {
            "status": "UNRESOLVED_PROVENANCE",
            "authorized": False,
            "target_grid_contract": None,
            "target_crs": None,
            "transform_source": None,
            "transform_revision": None,
            "transform_license": None,
            "transform_sha256": None,
            "required_before_authorization": EXPECTED_REQUIRED_PROVENANCE,
        },
        "authorization": {
            "road_identity_materialized": 0,
            "cell_assignment_materialized": 0,
            "registration_authorized": False,
            "render_authorized": False,
            "collision_authorized": False,
            "runtime_ready": False,
            "jouable": False,
        },
    }

    validate_crosswalk_precondition(payload, measurements_raw)

    assert measurements["source_evidence_git_blob_sha1"] == EXPECTED_EVIDENCE_GIT_BLOB_SHA1
    assert measurements["source"]["game_frame"] == EXPECTED_SOURCE_FRAME
    assert measurements["accounting"]["road_identity_materialized"] == 0
    assert measurements["accounting"]["cell_assignment_materialized"] == 0
    assert all(row["spatial_cell"] is None for row in measurements["municipalities"])
    assert all(row["cell_status"] == "NOT_ASSIGNED" for row in measurements["municipalities"])
    assert all(row["registration_authorized"] is False for row in measurements["municipalities"])
    assert all(row["render_authorized"] is False for row in measurements["municipalities"])
    assert all(row["collision_authorized"] is False for row in measurements["municipalities"])
    assert all(row["runtime_ready"] is False for row in measurements["municipalities"])
    assert all(row["jouable"] is False for row in measurements["municipalities"])


def test_json_loader_rejects_duplicate_precondition_keys() -> None:
    raw = b'{"schema":"grand-bruxelles-spatial-crosswalk-precondition-v1","schema":"shadowed"}\n'
    with pytest.raises(ValueError, match="duplicate JSON key: schema"):
        _load_json_no_duplicate_keys(raw, "spatial crosswalk precondition")


def test_json_loader_rejects_duplicate_measurement_keys() -> None:
    raw = b'{"accounting":{"road_identity_materialized":0,"road_identity_materialized":1}}\n'
    with pytest.raises(ValueError, match="duplicate JSON key: road_identity_materialized"):
        _load_json_no_duplicate_keys(raw, "source measurements")


def test_source_measurement_schema_rejects_unknown_fields() -> None:
    _, measurements, payload = _load()
    mutations = [
        lambda candidate: candidate.__setitem__("spatial_cell_candidate", "bxl-e150500-n170000-s500"),
        lambda candidate: candidate["source"].__setitem__("projection_guess", "EPSG:31370"),
        lambda candidate: candidate["accounting"].__setitem__("registered_municipalities", 7),
        lambda candidate: candidate["municipalities"][0].__setitem__("registration_authorised", True),
    ]
    for mutate in mutations:
        candidate_measurements = copy.deepcopy(measurements)
        mutate(candidate_measurements)
        with pytest.raises(ValueError, match="schema drift"):
            _validate_measurement_candidate(candidate_measurements, payload)


def test_source_measurement_provenance_rejects_repinned_drift() -> None:
    _, measurements, payload = _load()
    mutations = [
        lambda candidate: candidate["source"].__setitem__("provider", "unverified mirror"),
        lambda candidate: candidate["source"].__setitem__("license", "unknown"),
        lambda candidate: candidate["source"].__setitem__("endpoint", "https://example.invalid/overpass"),
        lambda candidate: candidate["source"]["acquisition_run"].__setitem__("run_id", 1),
        lambda candidate: candidate["source"]["acquisition_run"].__setitem__("source_pr", 1),
        lambda candidate: candidate["source"]["acquisition_run"].__setitem__("source_head_sha", "0" * 40),
    ]
    for mutate in mutations:
        candidate_measurements = copy.deepcopy(measurements)
        mutate(candidate_measurements)
        with pytest.raises(ValueError):
            _validate_measurement_candidate(candidate_measurements, payload)


def test_source_measurement_rows_reject_repinned_accounting_and_identity_drift() -> None:
    _, measurements, payload = _load()

    missing_row = copy.deepcopy(measurements)
    missing_row["municipalities"].pop()
    with pytest.raises(ValueError, match="locked_municipalities"):
        _validate_measurement_candidate(missing_row, payload)

    duplicate_identity = copy.deepcopy(measurements)
    duplicate_identity["municipalities"][1]["niscode"] = duplicate_identity["municipalities"][0]["niscode"]
    with pytest.raises(ValueError, match="duplicate niscode"):
        _validate_measurement_candidate(duplicate_identity, payload)

    materialized_identity = copy.deepcopy(measurements)
    materialized_identity["municipalities"][0]["road_identity_status"] = "MATERIALIZED"
    with pytest.raises(ValueError, match="road_identity_status"):
        _validate_measurement_candidate(materialized_identity, payload)

    invented_source_file = copy.deepcopy(measurements)
    invented_source_file["municipalities"][0]["source_file"] = "data/osm/invented.game.json"
    with pytest.raises(ValueError, match="source_file"):
        _validate_measurement_candidate(invented_source_file, payload)


def test_unresolved_crosswalk_rejects_any_premature_authorization() -> None:
    measurements_raw, _, payload = _load()
    mutations = [
        ("crosswalk", "authorized", True),
        ("authorization", "road_identity_materialized", 1),
        ("authorization", "cell_assignment_materialized", 1),
        ("authorization", "registration_authorized", True),
        ("authorization", "render_authorized", True),
        ("authorization", "collision_authorized", True),
        ("authorization", "runtime_ready", True),
        ("authorization", "jouable", True),
    ]
    for section, key, value in mutations:
        candidate = copy.deepcopy(payload)
        candidate[section][key] = value
        with pytest.raises(ValueError):
            validate_crosswalk_precondition(candidate, measurements_raw)


def test_closed_authorization_rejects_boolean_accounting_aliases() -> None:
    measurements_raw, _, payload = _load()
    for key in ("road_identity_materialized", "cell_assignment_materialized"):
        candidate = copy.deepcopy(payload)
        candidate["authorization"][key] = False
        with pytest.raises(ValueError):
            validate_crosswalk_precondition(candidate, measurements_raw)


def test_source_measurement_accounting_rejects_boolean_zero_aliases() -> None:
    measurements_raw, measurements, payload = _load()
    for key in ("road_identity_materialized", "cell_assignment_materialized"):
        candidate_measurements = copy.deepcopy(measurements)
        candidate_measurements["accounting"][key] = False
        candidate_raw = (json.dumps(candidate_measurements, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
        candidate_payload = copy.deepcopy(payload)
        candidate_payload["source_measurement_manifest"]["git_blob_sha1"] = _git_blob_sha1(candidate_raw)
        with pytest.raises(ValueError):
            validate_crosswalk_precondition(candidate_payload, candidate_raw)


def test_source_measurement_rows_reject_premature_cell_or_runtime_state() -> None:
    measurements_raw, measurements, payload = _load()
    mutations = [
        ("spatial_cell", "bxl-e150500-n170000-s500"),
        ("cell_status", "ASSIGNED"),
        ("registration_authorized", True),
        ("render_authorized", True),
        ("collision_authorized", True),
        ("runtime_ready", True),
        ("jouable", True),
    ]
    for key, value in mutations:
        candidate_measurements = copy.deepcopy(measurements)
        candidate_measurements["municipalities"][0][key] = value
        candidate_raw = (json.dumps(candidate_measurements, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
        candidate_payload = copy.deepcopy(payload)
        candidate_payload["source_measurement_manifest"]["git_blob_sha1"] = _git_blob_sha1(candidate_raw)
        with pytest.raises(ValueError):
            validate_crosswalk_precondition(candidate_payload, candidate_raw)


def test_authorized_crosswalk_requires_complete_pinned_provenance(tmp_path: Path) -> None:
    measurements_raw, _, payload = _load()
    grid_path = tmp_path / "data/qa/city_machine/example-grid.lock.json"
    grid_path.parent.mkdir(parents=True)
    grid_raw = b'{"schema":"example-grid-v1"}\n'
    grid_path.write_bytes(grid_raw)

    candidate = copy.deepcopy(payload)
    candidate["crosswalk"].update(
        {
            "status": "PROVENANCE_LOCKED",
            "authorized": True,
            "target_grid_contract": {
                "path": "data/qa/city_machine/example-grid.lock.json",
                "git_blob_sha1": _git_blob_sha1(grid_raw),
            },
            "target_crs": "EPSG:31370",
            "transform_source": "example-source",
            "transform_revision": "example-revision",
            "transform_license": "example-license",
            "transform_sha256": "a" * 64,
        }
    )
    validate_crosswalk_precondition(candidate, measurements_raw, repo_root=tmp_path)

    bad_candidates = []
    for key in EXPECTED_REQUIRED_PROVENANCE:
        bad = copy.deepcopy(candidate)
        bad["crosswalk"][key] = None
        bad_candidates.append(bad)

    malformed_grid_blob = copy.deepcopy(candidate)
    malformed_grid_blob["crosswalk"]["target_grid_contract"]["git_blob_sha1"] = "not-a-git-blob"
    bad_candidates.append(malformed_grid_blob)

    wrong_grid_blob = copy.deepcopy(candidate)
    wrong_grid_blob["crosswalk"]["target_grid_contract"]["git_blob_sha1"] = "1" * 40
    bad_candidates.append(wrong_grid_blob)

    missing_grid_path = copy.deepcopy(candidate)
    missing_grid_path["crosswalk"]["target_grid_contract"]["path"] = "data/qa/city_machine/missing.lock.json"
    bad_candidates.append(missing_grid_path)

    traversal_grid_path = copy.deepcopy(candidate)
    traversal_grid_path["crosswalk"]["target_grid_contract"]["path"] = "../outside.json"
    bad_candidates.append(traversal_grid_path)

    malformed_crs = copy.deepcopy(candidate)
    malformed_crs["crosswalk"]["target_crs"] = "31370"
    bad_candidates.append(malformed_crs)

    malformed_transform_hash = copy.deepcopy(candidate)
    malformed_transform_hash["crosswalk"]["transform_sha256"] = "ABC"
    bad_candidates.append(malformed_transform_hash)

    for bad in bad_candidates:
        with pytest.raises(ValueError):
            validate_crosswalk_precondition(bad, measurements_raw, repo_root=tmp_path)
