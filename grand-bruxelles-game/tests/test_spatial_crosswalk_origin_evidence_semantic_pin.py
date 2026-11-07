from __future__ import annotations

import json

import pytest

from tools.city_machine import validate_spatial_crosswalk_origin_evidence as validator


def test_primary_origin_evidence_validator_rejects_measurement_semantic_repin(tmp_path, monkeypatch):
    evidence = json.loads(validator.EVIDENCE_PATH.read_text(encoding="utf-8"))
    evidence["measured_contract"]["semantic_sha256"] = "0" * 64

    candidate = tmp_path / "origin-evidence.json"
    candidate.write_text(json.dumps(evidence), encoding="utf-8")
    monkeypatch.setattr(validator, "EVIDENCE_PATH", candidate)

    with pytest.raises(ValueError, match="measurement semantic immutable identity drift"):
        validator.validate()
