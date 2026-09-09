from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from tools.city_machine.validate_spatial_crosswalk_origin_artifact_receipt import validate_origin_artifact_receipt

EVIDENCE = ROOT / "data/source_plans/brussels_spatial_crosswalk_origin_evidence.lock.json"
RECEIPT = ROOT / "data/source_plans/brussels_spatial_crosswalk_origin_artifact_receipt.lock.json"
ROAD_SOURCE = ROOT / "data/osm/vertical_slice_01.game.json"
RUNTIME_INDEX = ROOT / "data/runtime/road_destination_runtime_index.json"


def _bytes(payload: dict) -> bytes:
    return (json.dumps(payload, indent=2) + "\n").encode("utf-8")


class OriginArtifactReceiptFailClosedTests(unittest.TestCase):
    def test_rejects_receipt_scope_note_rewrite(self) -> None:
        evidence_raw = EVIDENCE.read_bytes()
        receipt = json.loads(RECEIPT.read_text(encoding="utf-8"))
        receipt["scope_note"] = "Artifact metadata proves runtime authorization and JOUABLE readiness."
        with self.assertRaises(ValueError):
            validate_origin_artifact_receipt(evidence_raw, _bytes(receipt))

    def test_rejects_evidence_scope_note_rewrite(self) -> None:
        evidence = json.loads(EVIDENCE.read_text(encoding="utf-8"))
        receipt_raw = RECEIPT.read_bytes()
        evidence["scope_note"] = "Measured contract authorizes municipality assignment and runtime mounting."
        with self.assertRaises(ValueError):
            validate_origin_artifact_receipt(_bytes(evidence), receipt_raw)

    def test_rejects_measured_contract_semantic_digest_rewrite(self) -> None:
        evidence = json.loads(EVIDENCE.read_text(encoding="utf-8"))
        receipt_raw = RECEIPT.read_bytes()
        evidence["measured_contract"]["semantic_sha256"] = "0" * 64
        with self.assertRaises(ValueError):
            validate_origin_artifact_receipt(_bytes(evidence), receipt_raw)

    def test_rejects_measured_contract_parallel_field(self) -> None:
        evidence = json.loads(EVIDENCE.read_text(encoding="utf-8"))
        receipt_raw = RECEIPT.read_bytes()
        evidence["measured_contract"]["shadow_runtime_ready"] = True
        with self.assertRaises(ValueError):
            validate_origin_artifact_receipt(_bytes(evidence), receipt_raw)

    def test_rejects_road_source_byte_drift_with_locked_declared_hash(self) -> None:
        evidence_raw = EVIDENCE.read_bytes()
        receipt_raw = RECEIPT.read_bytes()
        road_source_raw = ROAD_SOURCE.read_bytes()
        mutated = road_source_raw + b"\n"
        with self.assertRaises(ValueError):
            validate_origin_artifact_receipt(evidence_raw, receipt_raw, mutated)

    def test_rejects_runtime_catalog_drift_with_locked_measured_contract(self) -> None:
        evidence_raw = EVIDENCE.read_bytes()
        receipt_raw = RECEIPT.read_bytes()
        original = RUNTIME_INDEX.read_bytes()
        runtime_index = json.loads(original.decode("utf-8"))
        runtime_index["catalog_sha256"] = "0" * 64
        try:
            RUNTIME_INDEX.write_bytes(_bytes(runtime_index))
            with self.assertRaises(ValueError):
                validate_origin_artifact_receipt(evidence_raw, receipt_raw)
        finally:
            RUNTIME_INDEX.write_bytes(original)


if __name__ == "__main__":
    unittest.main()
