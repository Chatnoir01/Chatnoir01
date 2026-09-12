from __future__ import annotations

import json
from pathlib import Path

import pytest

from tools.city_machine.validate_spatial_crosswalk_origin_artifact_receipt import validate_origin_artifact_receipt

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "data/source_plans/brussels_spatial_crosswalk_origin_evidence.lock.json"
RECEIPT = ROOT / "data/source_plans/brussels_spatial_crosswalk_origin_artifact_receipt.lock.json"


def _bytes(payload: dict) -> bytes:
    return (json.dumps(payload, indent=2) + "\n").encode("utf-8")


def test_rejects_receipt_scope_note_rewrite() -> None:
    evidence_raw = EVIDENCE.read_bytes()
    receipt = json.loads(RECEIPT.read_text(encoding="utf-8"))
    receipt["scope_note"] = "Artifact metadata proves runtime authorization and JOUABLE readiness."
    with pytest.raises(ValueError):
        validate_origin_artifact_receipt(evidence_raw, _bytes(receipt))


def test_rejects_evidence_scope_note_rewrite() -> None:
    evidence = json.loads(EVIDENCE.read_text(encoding="utf-8"))
    receipt_raw = RECEIPT.read_bytes()
    evidence["scope_note"] = "Measured contract authorizes municipality assignment and runtime mounting."
    with pytest.raises(ValueError):
        validate_origin_artifact_receipt(_bytes(evidence), receipt_raw)
