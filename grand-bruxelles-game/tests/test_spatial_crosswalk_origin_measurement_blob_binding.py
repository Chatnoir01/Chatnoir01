import importlib.util
import json
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "data/source_plans/brussels_spatial_crosswalk_origin_evidence.lock.json"
PRECONDITION = ROOT / "data/source_plans/brussels_spatial_crosswalk_precondition.lock.json"
MIDI_CANDIDATE = ROOT / "data/qa/city_machine/midi_onboarding_candidate.json"
MEASUREMENTS = ROOT / "data/source_plans/brussels_locked_road_source_measurements.lock.json"
SOURCE_EVIDENCE = ROOT / "data/source_plans/brussels_missing_road_source_acquisition_evidence.lock.json"


def _load_origin_validator():
    path = ROOT / "tools/city_machine/validate_spatial_crosswalk_origin_evidence.py"
    spec = importlib.util.spec_from_file_location("spatial_crosswalk_origin_validator_blob_binding", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _copy_common_inputs(tmp_path):
    evidence_path = tmp_path / "evidence.json"
    precondition_path = tmp_path / "precondition.json"
    midi_path = tmp_path / "midi.json"
    measurements_path = tmp_path / "measurements.json"
    source_evidence_path = tmp_path / "source-evidence.json"

    evidence_path.write_bytes(EVIDENCE.read_bytes())
    precondition_path.write_bytes(PRECONDITION.read_bytes())
    midi_path.write_bytes(MIDI_CANDIDATE.read_bytes())
    measurements_path.write_bytes(MEASUREMENTS.read_bytes())
    source_evidence_path.write_bytes(SOURCE_EVIDENCE.read_bytes())
    return evidence_path, precondition_path, midi_path, measurements_path, source_evidence_path


def _patch_paths(validator, monkeypatch, paths):
    evidence_path, precondition_path, midi_path, measurements_path, source_evidence_path = paths
    monkeypatch.setattr(validator, "EVIDENCE_PATH", evidence_path)
    monkeypatch.setattr(validator, "PRECONDITION_PATH", precondition_path)
    monkeypatch.setattr(validator, "MIDI_CANDIDATE_PATH", midi_path)
    monkeypatch.setattr(validator, "MEASUREMENTS_PATH", measurements_path, raising=False)
    monkeypatch.setattr(validator, "SOURCE_EVIDENCE_PATH", source_evidence_path, raising=False)


def test_origin_evidence_validator_rejects_measurement_file_blob_drift(tmp_path, monkeypatch):
    validator = _load_origin_validator()
    paths = _copy_common_inputs(tmp_path)
    measurements_path = paths[3]

    measurements = json.loads(measurements_path.read_text(encoding="utf-8"))
    measurements["accounting"]["locked_municipalities"] = 6
    measurements_path.write_text(json.dumps(measurements, separators=(",", ":")), encoding="utf-8")
    _patch_paths(validator, monkeypatch, paths)

    with pytest.raises(ValueError, match="source measurement manifest Git blob mismatch"):
        validator.validate()


def test_origin_evidence_validator_rejects_source_evidence_file_blob_drift(tmp_path, monkeypatch):
    validator = _load_origin_validator()
    paths = _copy_common_inputs(tmp_path)
    source_evidence_path = paths[4]

    source_evidence = json.loads(source_evidence_path.read_text(encoding="utf-8"))
    source_evidence["accounting"]["unresolved_municipalities"] = 8
    source_evidence_path.write_text(json.dumps(source_evidence, separators=(",", ":")), encoding="utf-8")
    _patch_paths(validator, monkeypatch, paths)

    with pytest.raises(ValueError, match="source acquisition evidence Git blob mismatch"):
        validator.validate()
