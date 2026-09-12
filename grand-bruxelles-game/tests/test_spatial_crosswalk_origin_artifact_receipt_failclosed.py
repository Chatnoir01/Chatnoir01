from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from tools.city_machine.validate_spatial_crosswalk_origin_artifact_receipt import (
    _load_json_strict,
    validate_origin_artifact_receipt,
)

EVIDENCE = ROOT / "data/source_plans/brussels_spatial_crosswalk_origin_evidence.lock.json"
RECEIPT = ROOT / "data/source_plans/brussels_spatial_crosswalk_origin_artifact_receipt.lock.json"
ROAD_SOURCE = ROOT / "data/osm/vertical_slice_01.game.json"
RUNTIME_INDEX = ROOT / "data/runtime/road_destination_runtime_index.json"
REGISTERED_CELL_INDEX = ROOT / "data/provenance/brussels_registered_cell_manifest_index.json"


def _bytes(payload: dict) -> bytes:
    return (json.dumps(payload, indent=2) + "\n").encode("utf-8")


class OriginArtifactReceiptFailClosedTests(unittest.TestCase):
    def test_strict_loader_rejects_nonstandard_json_constants(self) -> None:
        for token in (b"NaN", b"Infinity", b"-Infinity"):
            with self.subTest(token=token):
                with self.assertRaises(ValueError):
                    _load_json_strict(b'{"value": ' + token + b'}', "synthetic receipt")

    def test_strict_loader_rejects_finite_syntax_float_overflow(self) -> None:
        for token in (b"1e309", b"-1e309"):
            with self.subTest(token=token):
                with self.assertRaises(ValueError):
                    _load_json_strict(b'{"value": ' + token + b'}', "synthetic receipt")

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

    def test_rejects_valid_source_id_substitution_with_declared_catalog_digest_unchanged(self) -> None:
        evidence_raw = EVIDENCE.read_bytes()
        receipt_raw = RECEIPT.read_bytes()
        runtime_index = json.loads(RUNTIME_INDEX.read_text(encoding="utf-8"))
        source = json.loads(ROAD_SOURCE.read_text(encoding="utf-8"))
        road_ids = runtime_index["documents"][0]["road_ids"]
        source_ids = sorted({road["osm_id"] for road in source["roads"]})
        omitted = [road_id for road_id in source_ids if road_id not in set(road_ids)]
        self.assertEqual(len(omitted), 1)
        mutated = list(road_ids)
        mutated[0] = omitted[0]
        mutated.sort()
        self.assertEqual(len(mutated), len(road_ids))
        self.assertEqual(len(set(mutated)), len(mutated))
        self.assertTrue(set(mutated).issubset(set(source_ids)))
        runtime_index["documents"][0]["road_ids"] = mutated
        with self.assertRaises(ValueError):
            validate_origin_artifact_receipt(
                evidence_raw,
                receipt_raw,
                runtime_index_raw=_bytes(runtime_index),
            )

    def test_rejects_registered_cell_index_drift_with_locked_measured_contract(self) -> None:
        evidence_raw = EVIDENCE.read_bytes()
        receipt_raw = RECEIPT.read_bytes()
        original = REGISTERED_CELL_INDEX.read_bytes()
        registered_index = json.loads(original.decode("utf-8"))
        registered_index["registered_cell_count"] = 6
        try:
            REGISTERED_CELL_INDEX.write_bytes(_bytes(registered_index))
            with self.assertRaises(ValueError):
                validate_origin_artifact_receipt(evidence_raw, receipt_raw)
        finally:
            REGISTERED_CELL_INDEX.write_bytes(original)

    def test_rejects_registered_cell_index_production_base_repin(self) -> None:
        evidence_raw = EVIDENCE.read_bytes()
        receipt_raw = RECEIPT.read_bytes()
        original = REGISTERED_CELL_INDEX.read_bytes()
        registered_index = json.loads(original.decode("utf-8"))
        registered_index["production_base_sha"] = "0" * 40
        try:
            REGISTERED_CELL_INDEX.write_bytes(_bytes(registered_index))
            with self.assertRaises(ValueError):
                validate_origin_artifact_receipt(evidence_raw, receipt_raw)
        finally:
            REGISTERED_CELL_INDEX.write_bytes(original)


if __name__ == "__main__":
    unittest.main()
