from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from tools.city_machine.validate_spatial_crosswalk_origin_artifact_payload_lock import validate_payload_lock

LOCK = ROOT / "data/source_plans/brussels_spatial_crosswalk_origin_artifact_payload.lock.json"
RECEIPT = ROOT / "data/source_plans/brussels_spatial_crosswalk_origin_artifact_receipt.lock.json"


def _bytes(payload: dict) -> bytes:
    return (json.dumps(payload, indent=2) + "\n").encode("utf-8")


class OriginArtifactPayloadLockTests(unittest.TestCase):
    def test_accepts_locked_payload_identity(self) -> None:
        validate_payload_lock(LOCK.read_bytes(), RECEIPT.read_bytes())

    def test_rejects_payload_member_digest_drift(self) -> None:
        payload = json.loads(LOCK.read_text(encoding="utf-8"))
        payload["members"][0]["sha256"] = "0" * 64
        with self.assertRaises(ValueError):
            validate_payload_lock(_bytes(payload), RECEIPT.read_bytes())

    def test_rejects_parallel_runtime_authorization(self) -> None:
        payload = json.loads(LOCK.read_text(encoding="utf-8"))
        payload["authorization"]["runtime_mount_authorized"] = True
        with self.assertRaises(ValueError):
            validate_payload_lock(_bytes(payload), RECEIPT.read_bytes())

    def test_rejects_duplicate_member_key(self) -> None:
        raw = LOCK.read_text(encoding="utf-8")
        raw = raw.replace(
            '"name": "road_registered_cell_overlap_v2.json",',
            '"name": "shadow.json",\n      "name": "road_registered_cell_overlap_v2.json",',
            1,
        )
        with self.assertRaises(ValueError):
            validate_payload_lock(raw.encode("utf-8"), RECEIPT.read_bytes())

    def test_rejects_non_standard_json_constants(self) -> None:
        canonical = LOCK.read_text(encoding="utf-8")
        self.assertIn('"archive_size_in_bytes": 2473', canonical)
        for constant in ("NaN", "Infinity", "-Infinity"):
            with self.subTest(constant=constant):
                ambiguous = canonical.replace(
                    '"archive_size_in_bytes": 2473',
                    f'"archive_size_in_bytes": {constant}',
                    1,
                ).encode("utf-8")
                with self.assertRaisesRegex(ValueError, "non-standard JSON constant"):
                    validate_payload_lock(ambiguous, RECEIPT.read_bytes())


if __name__ == "__main__":
    unittest.main()
