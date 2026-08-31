from __future__ import annotations

import json
import math
import re
from datetime import datetime
from pathlib import Path

import pytest

PROJECT = Path(__file__).resolve().parents[1]
LOCK = PROJECT / "data/source_plans/brussels_missing_road_source_acquisition_evidence.lock.json"
REGISTRY = PROJECT / "data/source_plans/brussels_missing_road_source_registry.json"
WORKFLOW = PROJECT.parent / ".github/workflows/grand-bruxelles-missing-road-source-batch.yml"
AUDERGHEM_WORKFLOW = PROJECT.parent / ".github/workflows/grand-bruxelles-auderghem-road-source-acquisition.yml"

EXPECTED_SUCCESS = {"21002", "21005", "21007", "21011", "21016", "21017", "21019"}
EXPECTED_UNRESOLVED = {"21003", "21006", "21008", "21009", "21010", "21012", "21014", "21015", "21018"}
HEX64 = re.compile(r"^[0-9a-f]{64}$")
FORBIDDEN_UNRESOLVED_TOKENS = ("artifact", "sha", "hash", "timestamp", "bounds", "road_count", "point_count")
CLOSED_KEYS = ("source_registration_authorized", "road_cell_mapping_authorized", "render_authorized", "collision_authorized", "runtime_mount_authorized", "safe_spawn_authorized", "jouable_authorized")


def load(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    assert isinstance(value, dict)
    return value


def test_evidence_loader_rejects_duplicate_object_keys(tmp_path: Path) -> None:
    ambiguous = tmp_path / "ambiguous.lock.json"
    ambiguous.write_text(
        '{"format":"grand-bruxelles-missing-road-source-acquisition-evidence-v1",'
        '"authorization":{"runtime_mount_authorized":false,"runtime_mount_authorized":true}}',
        encoding="utf-8",
    )
    with pytest.raises(ValueError, match="duplicate JSON object key: runtime_mount_authorized"):
        load_json_strict(ambiguous)


def test_evidence_lock_is_exact_and_registry_bound() -> None:
    lock = load(LOCK); registry = load(REGISTRY)
    assert lock["format"] == "grand-bruxelles-missing-road-source-acquisition-evidence-v1"
    assert lock["source"] == {"provider":"OpenStreetMap contributors via Overpass API","license":"ODbL-1.0","endpoint":"https://overpass-api.de/api/interpreter","query_scope":"administrative_relation"}
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
        for key in ("niscode", "id", "name", "osm_relation_id"):
            assert row[key] == registry_by_nis[row["niscode"]][key]


def test_success_evidence_is_immutable_and_non_promoting() -> None:
    for row in load(LOCK)["successful_acquisitions"]:
        assert row["status"] == "ACQUIRED_ARTIFACT_LOCKED"
        artifact = row["artifact"]
        assert isinstance(artifact["id"], int) and artifact["id"] > 0
        assert artifact["name"] == f"road-source-{row['niscode']}-{row['id']}"
        assert HEX64.fullmatch(artifact["archive_sha256"])
        assert HEX64.fullmatch(row["raw_snapshot_semantic_sha256"])
        assert HEX64.fullmatch(row["normalized_game_source_semantic_sha256"])
        assert isinstance(row["road_count"], int) and row["road_count"] > 0
        assert isinstance(row["point_count"], int) and row["point_count"] >= row["road_count"]
        datetime.fromisoformat(row["osm_base_timestamp"].replace("Z", "+00:00"))
        bounds = row["bounds_m"]
        assert len(bounds) == 4 and all(isinstance(value, (int, float)) and math.isfinite(value) for value in bounds)
        assert bounds[0] < bounds[2] and bounds[1] < bounds[3]
        for key in CLOSED_KEYS: assert row["authorization"][key] is False


def test_unresolved_rows_make_no_immutable_or_runtime_claims() -> None:
    lock = load(LOCK)
    for row in lock["unresolved_acquisitions"]:
        assert row["status"] == "REMOTE_ACQUISITION_UNRESOLVED"
        lowered = {key.lower() for key in row}
        assert not any(any(token in key for token in FORBIDDEN_UNRESOLVED_TOKENS) for key in lowered)
    for key in CLOSED_KEYS: assert lock["authorization"][key] is False


def test_pull_request_validation_never_requeries_locked_successes() -> None:
    workflow = WORKFLOW.read_text(encoding="utf-8")
    assert "if: github.event_name == 'workflow_dispatch'" in workflow
    assert "tests/test_brussels_missing_road_source_acquisition_evidence_lock.py" in workflow
    assert "data/source_plans/brussels_missing_road_source_acquisition_evidence.lock.json" in workflow
    for nis in EXPECTED_SUCCESS: assert f"- {{nis: '{nis}'," not in workflow
    for nis in EXPECTED_UNRESOLVED: assert f"- {{nis: '{nis}'," in workflow


def test_auderghem_pull_request_uses_locked_evidence_not_network_reacquisition() -> None:
    workflow = AUDERGHEM_WORKFLOW.read_text(encoding="utf-8")
    assert "validate-locked-auderghem-evidence:" in workflow
    assert "if: github.event_name == 'workflow_dispatch'" in workflow
    assert "Reacquire source-backed Auderghem roads explicitly" in workflow
