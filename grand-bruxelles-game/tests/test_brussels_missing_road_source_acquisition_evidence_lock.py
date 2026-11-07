from __future__ import annotations

import json
import math
import re
from datetime import datetime, timezone
from pathlib import Path

import pytest

PROJECT = Path(__file__).resolve().parents[1]
LOCK = PROJECT / "data/source_plans/brussels_missing_road_source_acquisition_evidence.lock.json"
REGISTRY = PROJECT / "data/source_plans/brussels_missing_road_source_registry.json"
WORKFLOW = PROJECT.parent / ".github/workflows/grand-bruxelles-missing-road-source-batch.yml"
AUDERGHEM_WORKFLOW = PROJECT.parent / ".github/workflows/grand-bruxelles-auderghem-road-source-acquisition.yml"
EXPECTED_SUCCESS = {"21002", "21005", "21007", "21011", "21016", "21017", "21019"}
EXPECTED_UNRESOLVED = {"21003", "21006", "21008", "21009", "21010", "21012", "21014", "21015", "21018"}
EXPECTED_HIGHWAY_CLASSES = ["motorway", "trunk", "primary", "secondary", "tertiary", "unclassified", "residential", "living_street", "service"]
HEX64 = re.compile(r"^[0-9a-f]{64}$")
FORBIDDEN_UNRESOLVED_TOKENS = ("artifact", "sha", "hash", "timestamp", "bounds", "road_count", "point_count")
CLOSED_KEYS = ("source_registration_authorized", "road_cell_mapping_authorized", "render_authorized", "collision_authorized", "runtime_mount_authorized", "safe_spawn_authorized", "jouable_authorized")
ROOT_KEYS = {"format", "source", "game_frame", "acquisition_run", "accounting", "successful_acquisitions", "unresolved_acquisitions", "authorization"}
SUCCESS_KEYS = {"niscode", "id", "name", "osm_relation_id", "status", "artifact", "osm_base_timestamp", "road_count", "point_count", "bounds_m", "raw_snapshot_semantic_sha256", "normalized_game_source_semantic_sha256", "authorization"}
UNRESOLVED_KEYS = {"niscode", "id", "name", "osm_relation_id", "status"}


def reject_duplicate_object_keys(pairs: list[tuple[str, object]]) -> dict:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result: raise ValueError(f"duplicate JSON object key: {key}")
        result[key] = value
    return result


def load_json_strict(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=reject_duplicate_object_keys)
    assert isinstance(value, dict)
    return value


def load(path: Path) -> dict: return load_json_strict(path)


def assert_strict_positive_int(value: object) -> None:
    assert type(value) is int and value > 0


def assert_finite_number(value: object) -> None:
    assert type(value) in (int, float) and math.isfinite(value)


def test_numeric_evidence_helpers_reject_json_booleans() -> None:
    # bool is a subclass of int in Python; provenance gates must reject JSON true/false
    # wherever the schema requires an actual numeric value.
    with pytest.raises(AssertionError):
        assert_strict_positive_int(True)
    with pytest.raises(AssertionError):
        assert_finite_number(False)


def test_evidence_loader_rejects_duplicate_object_keys(tmp_path: Path) -> None:
    ambiguous = tmp_path / "ambiguous.lock.json"
    ambiguous.write_text('{"format":"grand-bruxelles-missing-road-source-acquisition-evidence-v1","authorization":{"runtime_mount_authorized":false,"runtime_mount_authorized":true}}', encoding="utf-8")
    with pytest.raises(ValueError, match="duplicate JSON object key: runtime_mount_authorized"): load_json_strict(ambiguous)


def test_evidence_lock_is_exact_and_registry_bound() -> None:
    lock = load(LOCK); registry = load(REGISTRY)
    assert set(lock) == ROOT_KEYS
    assert lock["format"] == "grand-bruxelles-missing-road-source-acquisition-evidence-v1"
    assert lock["source"] == {"provider":"OpenStreetMap contributors via Overpass API","license":"ODbL-1.0","endpoint":"https://overpass-api.de/api/interpreter","query_scope":"administrative_relation","highway_classes":EXPECTED_HIGHWAY_CLASSES,"query_timeout_seconds":120,"transport_timeout_seconds":150}
    assert lock["game_frame"] == registry["game_frame"]
    assert lock["acquisition_run"] == {"workflow":"Grand Bruxelles Missing Road Source Batch","run_id":33343196025,"source_pr":1675,"source_head_sha":"c9606e28eae99ef9dca77be53bb4e7a83cb94e7f"}
    assert lock["accounting"] == {"expected_municipalities":16,"successful_acquisitions":7,"unresolved_acquisitions":9}
    registry_by_nis = {row["niscode"]: row for row in registry["municipalities"]}
    success = lock["successful_acquisitions"]; unresolved = lock["unresolved_acquisitions"]
    assert {row["niscode"] for row in success} == EXPECTED_SUCCESS
    assert {row["niscode"] for row in unresolved} == EXPECTED_UNRESOLVED
    assert EXPECTED_SUCCESS | EXPECTED_UNRESOLVED == set(registry_by_nis)
    all_rows = success + unresolved
    assert len(all_rows) == 16
    assert len({row["niscode"] for row in all_rows}) == len({row["id"] for row in all_rows}) == len({row["osm_relation_id"] for row in all_rows}) == 16
    for row in all_rows:
        for key in ("niscode", "id", "name", "osm_relation_id"): assert row[key] == registry_by_nis[row["niscode"]][key]


def test_evidence_partition_order_and_accounting_are_registry_deterministic() -> None:
    lock = load(LOCK); registry = load(REGISTRY)
    registry_order = [row["niscode"] for row in registry["municipalities"]]
    success = lock["successful_acquisitions"]
    unresolved = lock["unresolved_acquisitions"]
    expected_success_order = [nis for nis in registry_order if nis in EXPECTED_SUCCESS]
    expected_unresolved_order = [nis for nis in registry_order if nis in EXPECTED_UNRESOLVED]
    assert [row["niscode"] for row in success] == expected_success_order
    assert [row["niscode"] for row in unresolved] == expected_unresolved_order
    assert lock["accounting"]["expected_municipalities"] == len(registry_order)
    assert lock["accounting"]["successful_acquisitions"] == len(success)
    assert lock["accounting"]["unresolved_acquisitions"] == len(unresolved)
    assert len(success) + len(unresolved) == len(registry_order)


def test_success_evidence_is_immutable_and_non_promoting() -> None:
    success = load(LOCK)["successful_acquisitions"]
    artifact_ids: set[int] = set()
    artifact_archives: set[str] = set()
    raw_semantic_hashes: set[str] = set()
    normalized_semantic_hashes: set[str] = set()
    for row in success:
        assert set(row) == SUCCESS_KEYS
        assert row["status"] == "ACQUIRED_ARTIFACT_LOCKED"
        artifact = row["artifact"]
        assert set(artifact) == {"id", "name", "archive_sha256"}
        assert_strict_positive_int(artifact["id"])
        assert artifact["id"] not in artifact_ids
        artifact_ids.add(artifact["id"])
        assert artifact["name"] == f"road-source-{row['niscode']}-{row['id']}"
        assert HEX64.fullmatch(artifact["archive_sha256"])
        assert artifact["archive_sha256"] not in artifact_archives
        artifact_archives.add(artifact["archive_sha256"])
        assert HEX64.fullmatch(row["raw_snapshot_semantic_sha256"])
        assert row["raw_snapshot_semantic_sha256"] not in raw_semantic_hashes
        raw_semantic_hashes.add(row["raw_snapshot_semantic_sha256"])
        assert HEX64.fullmatch(row["normalized_game_source_semantic_sha256"])
        assert row["normalized_game_source_semantic_sha256"] not in normalized_semantic_hashes
        normalized_semantic_hashes.add(row["normalized_game_source_semantic_sha256"])
        assert_strict_positive_int(row["road_count"])
        assert_strict_positive_int(row["point_count"])
        assert row["point_count"] >= row["road_count"]
        timestamp = row["osm_base_timestamp"]
        assert timestamp.endswith("Z")
        parsed_timestamp = datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
        assert parsed_timestamp.tzinfo is not None and parsed_timestamp.utcoffset() == timezone.utc.utcoffset(parsed_timestamp)
        bounds = row["bounds_m"]
        assert len(bounds) == 4
        for value in bounds:
            assert_finite_number(value)
        assert bounds[0] < bounds[2] and bounds[1] < bounds[3]
        assert set(row["authorization"]) == set(CLOSED_KEYS)
        for key in CLOSED_KEYS: assert row["authorization"][key] is False
    assert len(artifact_ids) == len(success)
    assert len(artifact_archives) == len(success)
    assert len(raw_semantic_hashes) == len(success)
    assert len(normalized_semantic_hashes) == len(success)


def test_unresolved_rows_make_no_immutable_or_runtime_claims() -> None:
    lock = load(LOCK)
    for row in lock["unresolved_acquisitions"]:
        assert set(row) == UNRESOLVED_KEYS
        assert row["status"] == "REMOTE_ACQUISITION_UNRESOLVED"
        lowered = {key.lower() for key in row}
        assert not any(any(token in key for token in FORBIDDEN_UNRESOLVED_TOKENS) for key in lowered)
    assert set(lock["authorization"]) == set(CLOSED_KEYS)
    for key in CLOSED_KEYS: assert lock["authorization"][key] is False


def test_pull_request_validation_never_requeries_locked_successes() -> None:
    workflow = WORKFLOW.read_text(encoding="utf-8")
    lock = load(LOCK)
    assert "if: github.event_name == 'workflow_dispatch'" in workflow
    assert "tests/test_brussels_missing_road_source_acquisition_evidence_lock.py" in workflow
    assert "tests/test_brussels_missing_road_source_transport_evidence.py" in workflow
    assert "data/source_plans/brussels_missing_road_source_acquisition_evidence.lock.json" in workflow
    for nis in EXPECTED_SUCCESS: assert f"- {{nis: '{nis}'," not in workflow
    for nis in EXPECTED_UNRESOLVED: assert f"- {{nis: '{nis}'," in workflow
    dispatch_rows = re.findall(r"- \{nis: '(\d{5})', id: ([a-z0-9_]+)\}", workflow)
    locked_unresolved_rows = [(row["niscode"], row["id"]) for row in lock["unresolved_acquisitions"]]
    assert dispatch_rows == locked_unresolved_rows
    assert len(dispatch_rows) == len(set(dispatch_rows))


def test_auderghem_workflow_is_validation_only_once_evidence_is_locked() -> None:
    workflow = AUDERGHEM_WORKFLOW.read_text(encoding="utf-8")
    assert "validate-locked-auderghem-evidence:" in workflow
    assert "tests/test_brussels_missing_road_source_acquisition_evidence_lock.py" in workflow
    assert "reacquire-auderghem-road-source:" not in workflow
    assert "Reacquire source-backed Auderghem roads explicitly" not in workflow
    assert "--manifest data/source_plans/auderghem_road_source_acquisition.json" not in workflow
    assert "auderghem-road-source-reacquisition" not in workflow