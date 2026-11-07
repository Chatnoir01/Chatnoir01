from __future__ import annotations

import copy
import json
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools/city_machine"
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

import validate_locked_osm_timestamp_provenance as validator

EVIDENCE = ROOT / "data/source_plans/brussels_missing_road_source_acquisition_evidence.lock.json"


def load_evidence() -> dict:
    return json.loads(EVIDENCE.read_text(encoding="utf-8"))


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("workflow", "Wrong Workflow"),
        ("source_pr", 1),
    ],
)
def test_timestamp_validator_rejects_pinned_run_identity_drift(tmp_path: Path, monkeypatch: pytest.MonkeyPatch, field: str, value):
    mutated = copy.deepcopy(load_evidence())
    mutated["acquisition_run"][field] = value
    path = tmp_path / "evidence.json"
    path.write_text(json.dumps(mutated), encoding="utf-8")
    monkeypatch.setattr(validator, "EVIDENCE", path)

    with pytest.raises(SystemExit, match="acquisition run provenance drift"):
        validator.main()


def test_timestamp_validator_rejects_acquisition_run_schema_drift(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    mutated = copy.deepcopy(load_evidence())
    mutated["acquisition_run"]["unexpected"] = True
    path = tmp_path / "evidence.json"
    path.write_text(json.dumps(mutated), encoding="utf-8")
    monkeypatch.setattr(validator, "EVIDENCE", path)

    with pytest.raises(SystemExit, match="acquisition run schema drift"):
        validator.main()
