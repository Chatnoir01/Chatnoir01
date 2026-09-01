from __future__ import annotations

import json
import re
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
LOCK = PROJECT / "data/source_plans/brussels_missing_road_source_acquisition_evidence.lock.json"
WORKFLOW = PROJECT.parent / ".github/workflows/grand-bruxelles-missing-road-source-batch.yml"


def load(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    assert isinstance(value, dict)
    return value


def test_dispatch_matrix_is_derived_exactly_from_immutable_unresolved_lock() -> None:
    lock = load(LOCK)
    workflow = WORKFLOW.read_text(encoding="utf-8")
    expected = {(row["niscode"], row["id"]) for row in lock["unresolved_acquisitions"]}
    selected = set(re.findall(r"- \{nis: '(\d+)', id: ([a-z0-9_]+)\}", workflow))
    assert selected == expected
    locked = {row["niscode"] for row in lock["successful_acquisitions"]}
    assert not locked & {nis for nis, _ in selected}


def test_dispatch_fails_closed_against_lock_before_any_remote_acquisition() -> None:
    workflow = WORKFLOW.read_text(encoding="utf-8")
    guard = "Fail closed unless selection is unresolved in immutable evidence lock"
    assert guard in workflow
    guard_pos = workflow.index(guard)
    build_pos = workflow.index("Build locked municipality manifest")
    acquire_pos = workflow.index("Acquire unresolved source-backed roads")
    assert guard_pos < build_pos < acquire_pos
    guard_block = workflow[guard_pos:build_pos]
    assert "brussels_missing_road_source_acquisition_evidence.lock.json" in guard_block
    assert "SELECTED_NIS" in guard_block
    assert "SELECTED_ID" in guard_block
    assert "successful_acquisitions" in guard_block
    assert "unresolved_acquisitions" in guard_block
    assert "already locked" in guard_block
