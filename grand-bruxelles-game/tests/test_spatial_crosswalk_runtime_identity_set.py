from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from tools.city_machine.validate_spatial_crosswalk_runtime_identity_set import validate_runtime_identity_set

RUNTIME_INDEX = ROOT / "data/runtime/road_destination_runtime_index.json"
ROAD_SOURCE = ROOT / "data/osm/vertical_slice_01.game.json"


def _bytes(payload: dict) -> bytes:
    return json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8")


class RuntimeIdentitySetTests(unittest.TestCase):
    def test_canonical_runtime_identity_set_is_valid(self) -> None:
        validate_runtime_identity_set(RUNTIME_INDEX.read_bytes(), ROAD_SOURCE.read_bytes())

    def test_rejects_valid_source_id_substitution_with_declared_catalog_digest_unchanged(self) -> None:
        runtime = json.loads(RUNTIME_INDEX.read_text(encoding="utf-8"))
        source = json.loads(ROAD_SOURCE.read_text(encoding="utf-8"))
        road_ids = runtime["documents"][0]["road_ids"]
        source_ids = sorted({road["osm_id"] for road in source["roads"]})
        omitted = [road_id for road_id in source_ids if road_id not in set(road_ids)]
        self.assertEqual(len(omitted), 1)
        mutated = list(road_ids)
        mutated[0] = omitted[0]
        mutated.sort()
        self.assertEqual(len(mutated), len(road_ids))
        self.assertEqual(len(set(mutated)), len(mutated))
        self.assertTrue(set(mutated).issubset(set(source_ids)))
        runtime["documents"][0]["road_ids"] = mutated
        with self.assertRaises(ValueError):
            validate_runtime_identity_set(_bytes(runtime), ROAD_SOURCE.read_bytes())

    def test_rejects_duplicate_runtime_json_key_even_when_last_value_is_valid(self) -> None:
        canonical = RUNTIME_INDEX.read_text(encoding="utf-8")
        self.assertIn('"source_lookup_only":true', canonical)
        ambiguous = canonical.replace(
            '"source_lookup_only":true',
            '"source_lookup_only":false,"source_lookup_only":true',
            1,
        ).encode("utf-8")
        with self.assertRaisesRegex(ValueError, "duplicate JSON key: source_lookup_only"):
            validate_runtime_identity_set(ambiguous, ROAD_SOURCE.read_bytes())

    def test_rejects_duplicate_source_json_key_even_when_last_value_is_valid(self) -> None:
        canonical = ROAD_SOURCE.read_text(encoding="utf-8")
        self.assertIn('"license":"ODbL-1.0"', canonical)
        ambiguous = canonical.replace(
            '"license":"ODbL-1.0"',
            '"license":"ambiguous","license":"ODbL-1.0"',
            1,
        ).encode("utf-8")
        with self.assertRaisesRegex(ValueError, "duplicate JSON key: license"):
            validate_runtime_identity_set(RUNTIME_INDEX.read_bytes(), ambiguous)

    def test_rejects_non_standard_runtime_json_constants(self) -> None:
        canonical = RUNTIME_INDEX.read_text(encoding="utf-8")
        self.assertIn('"source_lookup_only":true', canonical)
        for constant in ("NaN", "Infinity", "-Infinity"):
            with self.subTest(constant=constant):
                ambiguous = canonical.replace(
                    '"source_lookup_only":true',
                    f'"shadow_numeric":{constant},"source_lookup_only":true',
                    1,
                ).encode("utf-8")
                with self.assertRaisesRegex(ValueError, "non-standard JSON constant"):
                    validate_runtime_identity_set(ambiguous, ROAD_SOURCE.read_bytes())

    def test_rejects_non_standard_source_json_constants(self) -> None:
        canonical = ROAD_SOURCE.read_text(encoding="utf-8")
        self.assertIn('"license":"ODbL-1.0"', canonical)
        for constant in ("NaN", "Infinity", "-Infinity"):
            with self.subTest(constant=constant):
                ambiguous = canonical.replace(
                    '"license":"ODbL-1.0"',
                    f'"shadow_numeric":{constant},"license":"ODbL-1.0"',
                    1,
                ).encode("utf-8")
                with self.assertRaisesRegex(ValueError, "non-standard JSON constant"):
                    validate_runtime_identity_set(RUNTIME_INDEX.read_bytes(), ambiguous)


if __name__ == "__main__":
    unittest.main()
