#!/usr/bin/env python3
import copy
import unittest

from validate_cell_manifest import validate

BASE = {
    "format": "grand-bruxelles-cell-maturity-v1",
    "cell_id": "test-cell",
    "crs": "EPSG:31370",
    "bbox": [0.0, 0.0, 500.0, 500.0],
    "maturity": {"state": "data_ready", "gates": {
        "runtime_geometry": False, "collisions": False, "streaming": False,
        "terrain": False, "heights": False, "photo_match": False, "performance": False}},
    "provenance": {"source_records_present": True},
    "geometry": {"authoritative_geometry_ready": True},
    "terrain": {"status": "pending"},
    "heights": {"status": "pending"},
    "collisions": {"status": "pending"},
    "transport": {},
    "photo_match": {"required": False, "open_major_mismatches": 0},
    "performance": {"status": "pending"},
    "uncertainties": ["pending realism work"]
}


class CellManifestValidationTests(unittest.TestCase):
    def test_data_ready_allows_explicit_pending_work(self):
        validate(copy.deepcopy(BASE))

    def test_playable_requires_runtime_collision_streaming(self):
        candidate = copy.deepcopy(BASE)
        candidate["maturity"]["state"] = "playable"
        with self.assertRaisesRegex(ValueError, "runtime_geometry"):
            validate(candidate)

    def test_invalidated_heights_cannot_pass_height_gate(self):
        candidate = copy.deepcopy(BASE)
        candidate["heights"]["status"] = "invalidated"
        candidate["maturity"]["gates"]["heights"] = True
        with self.assertRaisesRegex(ValueError, "invalidated height evidence"):
            validate(candidate)

    def test_realism_validated_requires_no_uncertainty(self):
        candidate = copy.deepcopy(BASE)
        candidate["maturity"]["state"] = "realism_validated"
        for gate in candidate["maturity"]["gates"]:
            candidate["maturity"]["gates"][gate] = True
        with self.assertRaisesRegex(ValueError, "unresolved uncertainties"):
            validate(candidate)

    def test_realism_validated_blocks_major_photo_mismatch(self):
        candidate = copy.deepcopy(BASE)
        candidate["maturity"]["state"] = "realism_validated"
        candidate["uncertainties"] = []
        for gate in candidate["maturity"]["gates"]:
            candidate["maturity"]["gates"][gate] = True
        candidate["photo_match"] = {"required": True, "open_major_mismatches": 1}
        with self.assertRaisesRegex(ValueError, "zero major photo-match"):
            validate(candidate)


if __name__ == "__main__":
    unittest.main()
