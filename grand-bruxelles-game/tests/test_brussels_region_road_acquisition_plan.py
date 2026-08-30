from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
BUILDER = PROJECT / "tools/build_brussels_region_road_acquisition_plan.py"
TARGET = PROJECT / "data/qa/brussels_region_playability_target.json"
READINESS = PROJECT / "data/provenance/brussels_road_destination_readiness_catalog.json"
EXPECTED_NISCODES = [f"210{value:02d}" for value in range(1, 20)]


def run_builder(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(BUILDER), *args],
        cwd=PROJECT,
        text=True,
        capture_output=True,
        check=False,
    )


def test_plan_covers_exactly_19_municipalities_without_opening_runtime(tmp_path: Path) -> None:
    output = tmp_path / "plan.json"
    result = run_builder("--output", str(output))
    assert result.returncode == 0, result.stdout + result.stderr
    plan = json.loads(output.read_text(encoding="utf-8"))

    assert plan["schema"] == "grand-bruxelles-region-road-acquisition-plan-v1"
    assert plan["municipality_count"] == 19
    assert [row["niscode"] for row in plan["municipalities"]] == EXPECTED_NISCODES
    assert sorted(plan["covered_niscodes"] + plan["missing_niscodes"]) == EXPECTED_NISCODES
    assert plan["municipalities_with_registered_road_evidence"] + plan["municipalities_without_registered_road_evidence"] == 19
    assert len(plan["acquisition_priority_niscodes"]) == 19
    assert sorted(plan["acquisition_priority_niscodes"]) == EXPECTED_NISCODES
    assert plan["regional_playability_complete"] is False
    assert len(plan["plan_sha256"]) == 64

    for row in plan["municipalities"]:
        assert row["playable_claimed"] is False
        assert row["acquisition_state"] in {
            "ACQUIRE_FIRST_REGISTERED_EVIDENCE",
            "EXPAND_REGISTERED_EVIDENCE",
        }
        assert row["source_registration_evidence_present"] == (row["registered_road_evidence_count"] > 0)
        assert row["registered_road_evidence_count"] == len(row["registered_road_osm_ids"])

    auth = plan["authorization"]
    assert auth["evidence_only"] is True
    for key in (
        "source_registration_authorized",
        "road_cell_mapping_authorized",
        "render_authorized",
        "collision_authorized",
        "runtime_mount_authorized",
        "safe_spawn_authorized",
        "jouable_authorized",
    ):
        assert auth[key] is False, key


def test_plan_is_deterministic(tmp_path: Path) -> None:
    first = tmp_path / "first.json"
    second = tmp_path / "second.json"
    result_first = run_builder("--output", str(first))
    result_second = run_builder("--output", str(second))
    assert result_first.returncode == 0, result_first.stdout + result_first.stderr
    assert result_second.returncode == 0, result_second.stdout + result_second.stderr
    assert first.read_bytes() == second.read_bytes()


def test_plan_prioritizes_municipalities_without_registered_evidence(tmp_path: Path) -> None:
    output = tmp_path / "plan.json"
    result = run_builder("--output", str(output))
    assert result.returncode == 0, result.stdout + result.stderr
    plan = json.loads(output.read_text(encoding="utf-8"))
    missing = set(plan["missing_niscodes"])
    seen_covered = False
    for nis in plan["acquisition_priority_niscodes"]:
        if nis not in missing:
            seen_covered = True
        if nis in missing:
            assert not seen_covered, "a covered municipality was prioritized before a zero-evidence municipality"


def test_plan_rejects_target_with_less_than_19_municipalities(tmp_path: Path) -> None:
    target = json.loads(TARGET.read_text(encoding="utf-8"))
    target["required_municipalities"] = target["required_municipalities"][:-1]
    modified = tmp_path / "target.json"
    modified.write_text(json.dumps(target), encoding="utf-8")
    result = run_builder("--target", str(modified), "--output", str(tmp_path / "plan.json"))
    assert result.returncode != 0
    assert "exactly 19 municipalities" in result.stdout + result.stderr


def test_plan_rejects_open_readiness_runtime_authorization(tmp_path: Path) -> None:
    readiness = json.loads(READINESS.read_text(encoding="utf-8"))
    readiness["authorization"]["runtime_mount_authorized"] = True
    modified = tmp_path / "readiness.json"
    modified.write_text(json.dumps(readiness), encoding="utf-8")
    result = run_builder("--readiness", str(modified), "--output", str(tmp_path / "plan.json"))
    assert result.returncode != 0
    assert "readiness opened runtime_mount_authorized" in result.stdout + result.stderr
