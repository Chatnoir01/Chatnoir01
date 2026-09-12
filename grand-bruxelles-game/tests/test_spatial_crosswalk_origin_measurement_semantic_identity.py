import importlib.util
import json
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "data/source_plans/brussels_spatial_crosswalk_origin_evidence.lock.json"


def _load_validator():
    path = ROOT / "tools/city_machine/validate_spatial_crosswalk_origin_measurement_semantic_identity.py"
    spec = importlib.util.spec_from_file_location("origin_measurement_semantic_validator", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_origin_measurement_semantic_identity_is_canonical():
    validator = _load_validator()
    validator.validate()


def test_origin_measurement_semantic_identity_repin_fails_closed(tmp_path, monkeypatch):
    validator = _load_validator()
    evidence = json.loads(EVIDENCE.read_text(encoding="utf-8"))
    evidence["measured_contract"]["semantic_sha256"] = "0" * 64

    evidence_path = tmp_path / "evidence.json"
    evidence_path.write_text(json.dumps(evidence), encoding="utf-8")
    monkeypatch.setattr(validator, "EVIDENCE_PATH", evidence_path)

    with pytest.raises(ValueError, match="measurement semantic immutable identity drift"):
        validator.validate()


def test_origin_measurement_semantic_identity_rejects_measured_contract_schema_extension(tmp_path, monkeypatch):
    validator = _load_validator()
    evidence = json.loads(EVIDENCE.read_text(encoding="utf-8"))
    evidence["measured_contract"]["shadow_semantic_sha256"] = evidence["measured_contract"]["semantic_sha256"]

    evidence_path = tmp_path / "evidence.json"
    evidence_path.write_text(json.dumps(evidence), encoding="utf-8")
    monkeypatch.setattr(validator, "EVIDENCE_PATH", evidence_path)

    with pytest.raises(ValueError, match="origin evidence measured_contract schema drift"):
        validator.validate()
