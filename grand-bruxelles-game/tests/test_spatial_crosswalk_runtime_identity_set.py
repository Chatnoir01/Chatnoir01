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


if __name__ == "__main__":
    unittest.main()
