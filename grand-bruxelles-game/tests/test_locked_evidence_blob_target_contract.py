from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools/city_machine"
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

import validate_locked_evidence_blob as validator


def test_pin_rejects_retargeted_same_blob(tmp_path, monkeypatch):
    payload = b'{"immutable":"evidence"}\n'
    canonical = tmp_path / "data/source_plans/brussels_missing_road_source_acquisition_evidence.lock.json"
    canonical.parent.mkdir(parents=True)
    canonical.write_bytes(payload)
    alternate = tmp_path / "data/source_plans/copied-evidence.lock.json"
    alternate.write_bytes(payload)

    pin = tmp_path / "pin.json"
    pin.write_text(
        json.dumps(
            {
                "schema": validator.PIN_SCHEMA,
                "target_path": "data/source_plans/copied-evidence.lock.json",
                "git_blob_sha1": validator.git_blob_sha1(payload),
            }
        ),
        encoding="utf-8",
    )
    monkeypatch.setattr(validator, "ROOT", tmp_path)

    with pytest.raises(SystemExit, match="target path contract drift"):
        validator.validate_pin(pin)


def test_pin_rejects_coordinated_evidence_and_pin_drift(tmp_path, monkeypatch):
    payload = b'{"mutated":"evidence"}\n'
    canonical = tmp_path / "data/source_plans/brussels_missing_road_source_acquisition_evidence.lock.json"
    canonical.parent.mkdir(parents=True)
    canonical.write_bytes(payload)

    pin = tmp_path / "pin.json"
    pin.write_text(
        json.dumps(
            {
                "schema": validator.PIN_SCHEMA,
                "target_path": validator.EXPECTED_TARGET_PATH,
                "git_blob_sha1": validator.git_blob_sha1(payload),
            }
        ),
        encoding="utf-8",
    )
    monkeypatch.setattr(validator, "ROOT", tmp_path)

    with pytest.raises(SystemExit, match="Git blob pin contract drift"):
        validator.validate_pin(pin)
