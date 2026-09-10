from __future__ import annotations

import hashlib
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from tools.city_machine.validate_registered_cell_manifest_index_identity import validate_registered_cell_manifest_index_identity
from tools.city_machine.validate_spatial_crosswalk_geometric_overlap_relations import validate_overlap_relation_lock

LOCK = ROOT / "data/source_plans/brussels_spatial_crosswalk_geometric_overlap_relations.lock.json"
SOURCE = ROOT / "data/osm/vertical_slice_01.game.json"
RUNTIME = ROOT / "data/runtime/road_destination_runtime_index.json"
CELLS = ROOT / "data/provenance/brussels_registered_cell_manifest_index.json"
PAYLOAD_LOCK = ROOT / "data/source_plans/brussels_spatial_crosswalk_origin_artifact_payload.lock.json"


def _bytes(payload: dict) -> bytes:
    return (json.dumps(payload, indent=2, ensure_ascii=False) + "\n").encode("utf-8")


def _relation_digest(relations: list[dict]) -> str:
    canonical = "".join(
        f"{entry['osm_id']}\t{entry['cell_id']}\n"
        for entry in sorted(relations, key=lambda item: (item["osm_id"], item["cell_id"]))
    ).encode("utf-8")
    return hashlib.sha256(canonical).hexdigest()


class GeometricOverlapRelationLockTests(unittest.TestCase):
    def _validate(self, lock_raw: bytes, cells_raw: bytes | None = None) -> None:
        effective_cells_raw = CELLS.read_bytes() if cells_raw is None else cells_raw
        validate_registered_cell_manifest_index_identity(effective_cells_raw)
        validate_overlap_relation_lock(
            lock_raw,
            SOURCE.read_bytes(),
            RUNTIME.read_bytes(),
            effective_cells_raw,
            PAYLOAD_LOCK.read_bytes(),
        )

    def _validate_direct(self, lock_raw: bytes, cells_raw: bytes) -> None:
        validate_overlap_relation_lock(
            lock_raw,
            SOURCE.read_bytes(),
            RUNTIME.read_bytes(),
            cells_raw,
            PAYLOAD_LOCK.read_bytes(),
        )

    def test_canonical_relation_lock_reproduces_exact_geometry(self) -> None:
        self._validate(LOCK.read_bytes())

    def test_rejects_same_count_relation_substitution(self) -> None:
        lock = json.loads(LOCK.read_text(encoding="utf-8"))
        relations = lock["relations"]
        original_count = len(relations)
        original = relations[0]
        candidate_cells = sorted(
            entry["cell_id"]
            for entry in json.loads(CELLS.read_text(encoding="utf-8"))["entries"]
            if entry["cell_id"] != original["cell_id"]
        )
        self.assertTrue(candidate_cells)
        relations[0] = {"osm_id": original["osm_id"], "cell_id": candidate_cells[0]}
        relations.sort(key=lambda item: (item["osm_id"], item["cell_id"]))
        self.assertEqual(len(relations), original_count)
        lock["relation_semantic_sha256"] = _relation_digest(relations)
        with self.assertRaises(ValueError):
            self._validate(_bytes(lock))

    def test_rejects_registered_cell_manifest_identity_drift_even_when_declared_semantic_digest_is_unchanged(self) -> None:
        cells = json.loads(CELLS.read_text(encoding="utf-8"))
        self.assertEqual(cells["semantic_sha256"], "8dd6b8994160b7a22b83f8be4ce63cfa4b579f724d51b3896c0426782b259187")
        cells["entries"][0]["manifest_sha256"] = "0" * 64
        with self.assertRaises(ValueError):
            self._validate(LOCK.read_bytes(), _bytes(cells))

    def test_direct_validator_rejects_registered_cell_manifest_identity_drift(self) -> None:
        cells = json.loads(CELLS.read_text(encoding="utf-8"))
        cells["entries"][0]["manifest_sha256"] = "0" * 64
        with self.assertRaises(ValueError):
            self._validate_direct(LOCK.read_bytes(), _bytes(cells))

    def test_registered_cell_index_rejects_nonstandard_json_constants(self) -> None:
        raw = CELLS.read_text(encoding="utf-8")
        for constant in ("NaN", "Infinity", "-Infinity"):
            ambiguous = raw.replace('"registered_cell_count": 5,', f'"registered_cell_count": {constant},', 1).encode("utf-8")
            with self.subTest(constant=constant):
                with self.assertRaisesRegex(ValueError, f"non-standard JSON constant: {constant}"):
                    validate_registered_cell_manifest_index_identity(ambiguous)

    def test_rejects_authorization_opening(self) -> None:
        lock = json.loads(LOCK.read_text(encoding="utf-8"))
        lock["authorization"]["road_cell_mapping_authorized"] = True
        with self.assertRaises(ValueError):
            self._validate(_bytes(lock))

    def test_rejects_duplicate_json_key_even_when_last_value_is_closed(self) -> None:
        raw = LOCK.read_text(encoding="utf-8")
        ambiguous = raw.replace(
            '"road_cell_mapping_authorized": false,',
            '"road_cell_mapping_authorized": true,\n    "road_cell_mapping_authorized": false,',
            1,
        ).encode("utf-8")
        with self.assertRaisesRegex(ValueError, "duplicate JSON key: road_cell_mapping_authorized"):
            self._validate(ambiguous)

    def test_rejects_nonstandard_nan_before_semantic_validation(self) -> None:
        raw = LOCK.read_text(encoding="utf-8")
        ambiguous = raw.replace('"overlapping_road_count": 64,', '"overlapping_road_count": NaN,', 1).encode("utf-8")
        with self.assertRaisesRegex(ValueError, "non-standard JSON constant: NaN"):
            self._validate(ambiguous)


if __name__ == "__main__":
    unittest.main()
