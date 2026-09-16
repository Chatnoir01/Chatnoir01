import importlib.util
import json
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "data/source_plans/brussels_spatial_crosswalk_origin_evidence.lock.json"
PRECONDITION = ROOT / "data/source_plans/brussels_spatial_crosswalk_precondition.lock.json"
MIDI_CANDIDATE = ROOT / "data/qa/city_machine/midi_onboarding_candidate.json"


def _load_origin_validator():
    path = ROOT / "tools/city_machine/validate_spatial_crosswalk_origin_evidence.py"
    spec = importlib.util.spec_from_file_location("spatial_crosswalk_origin_validator", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def _run_with_precondition(tmp_path, monkeypatch, precondition):
    validator = _load_origin_validator()
    evidence_path = tmp_path / "evidence.json"
    precondition_path = tmp_path / "precondition.json"
    midi_path = tmp_path / "midi.json"
    evidence_path.write_text(EVIDENCE.read_text(encoding="utf-8"), encoding="utf-8")
    precondition_path.write_text(json.dumps(precondition), encoding="utf-8")
    midi_path.write_text(MIDI_CANDIDATE.read_text(encoding="utf-8"), encoding="utf-8")
    monkeypatch.setattr(validator, "EVIDENCE_PATH", evidence_path)
    monkeypatch.setattr(validator, "PRECONDITION_PATH", precondition_path)
    monkeypatch.setattr(validator, "MIDI_CANDIDATE_PATH", midi_path)
    validator.validate()


def test_origin_validator_rejects_shadow_crosswalk_provenance_key(tmp_path, monkeypatch):
    precondition = _load(PRECONDITION)
    precondition["crosswalk"]["shadow_transform_sha256"] = "0" * 64

    with pytest.raises(ValueError, match="crosswalk schema drift"):
        _run_with_precondition(tmp_path, monkeypatch, precondition)


def test_origin_validator_rejects_shadow_precondition_top_level_key(tmp_path, monkeypatch):
    precondition = _load(PRECONDITION)
    precondition["shadow_authorization"] = {"runtime_mount_authorized": True}

    with pytest.raises(ValueError, match="spatial crosswalk precondition schema drift"):
        _run_with_precondition(tmp_path, monkeypatch, precondition)


def test_origin_validator_rejects_source_measurement_manifest_repin(tmp_path, monkeypatch):
    precondition = _load(PRECONDITION)
    precondition["source_measurement_manifest"]["git_blob_sha1"] = "0" * 40

    with pytest.raises(ValueError, match="source measurement manifest immutable identity drift"):
        _run_with_precondition(tmp_path, monkeypatch, precondition)


def test_origin_validator_rejects_precondition_authorization_open(tmp_path, monkeypatch):
    precondition = _load(PRECONDITION)
    precondition["authorization"]["registration_authorized"] = True

    with pytest.raises(ValueError, match="precondition authorization rails must remain closed"):
        _run_with_precondition(tmp_path, monkeypatch, precondition)
