#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import shutil
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPORT_ROOT = ROOT / "data" / "qa" / "player_reports"
SCHEMA_PATH = REPORT_ROOT / "player-report-v1.schema.json"
FIXTURE_PATH = REPORT_ROOT / "fixtures" / "anneessens-open-example.gbreport.json"
RUNTIME_PATH = ROOT / "game" / "scripts" / "player_issue_report_runtime.gd"
CONTINUITY_PATH = ROOT / "tools" / "continuity" / "continuity.py"
EXPECTED_SCHEMA = "grand-bruxelles-player-report-v1"


def _load_continuity_module():
    spec = importlib.util.spec_from_file_location("gb_continuity", CONTINUITY_PATH)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_player_report_repo_contract() -> None:
    assert (REPORT_ROOT / "open" / ".gitkeep").exists()
    assert (REPORT_ROOT / "archive" / ".gitkeep").exists()
    assert (REPORT_ROOT / "README.md").exists()

    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    assert schema["$id"] == EXPECTED_SCHEMA
    assert schema["properties"]["schema"]["const"] == EXPECTED_SCHEMA
    required = set(schema["required"])
    assert {"schema", "id", "status", "zone", "player_position", "note", "captured_unix"} <= required
    assert schema["properties"]["player_position"]["minItems"] == 3
    assert schema["properties"]["player_position"]["maxItems"] == 3
    assert schema["properties"]["note"]["maxLength"] == 80
    assert "build" in schema["properties"]
    assert "sha" in schema["properties"]["build"]["properties"]

    runtime = RUNTIME_PATH.read_text(encoding="utf-8")
    assert f'const SCHEMA := "{EXPECTED_SCHEMA}"' in runtime
    assert 'const REPORT_DIR := "user://player_reports/open"' in runtime
    assert '"player_position"' in runtime
    assert '"captured_unix"' in runtime

    fixture = json.loads(FIXTURE_PATH.read_text(encoding="utf-8"))
    assert fixture["schema"] == EXPECTED_SCHEMA
    assert fixture["status"] == "open"
    assert fixture["zone"]["id"] == "anneessens"
    assert len(fixture["player_position"]) == 3
    assert fixture["note"]
    assert fixture["captured_unix"] > 0
    assert fixture["build"]["source"] == "synthetic_test_fixture"

    continuity = _load_continuity_module()
    assert continuity.REPORT_SCHEMA == EXPECTED_SCHEMA
    with tempfile.TemporaryDirectory() as tmp:
        target = Path(tmp) / FIXTURE_PATH.name
        shutil.copyfile(FIXTURE_PATH, target)
        reports = continuity.read_reports(Path(tmp))
    assert len(reports) == 1
    assert reports[0]["id"] == "fixture-anneessens-001"
    assert reports[0]["zone"]["id"] == "anneessens"


if __name__ == "__main__":
    test_player_report_repo_contract()
    print("PLAYER_REPORT_REPO_CONTRACT_OK schema=grand-bruxelles-player-report-v1 fixture=anneessens-open-example")
