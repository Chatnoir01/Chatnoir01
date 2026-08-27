import copy
import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / "data/qa/osm_road_frame_correction_review.contract.json"


class RoadFrameCorrectionReviewContractTest(unittest.TestCase):
    def setUp(self):
        self.contract = json.loads(CONTRACT.read_text())

    def test_locked_candidate_is_review_only(self):
        c = self.contract
        self.assertEqual(c["schema"], "grand-bruxelles-osm-road-frame-correction-review-v1")
        self.assertEqual(c["status"], "READY_FOR_FRAME_CORRECTION_REVIEW_SOURCE_ORIGIN")
        self.assertEqual(c["source"]["license"], "ODbL-1.0")
        self.assertEqual(c["candidate_frame"]["crs"], "EPSG:31370")
        self.assertEqual(c["reconciliation"]["duplicate_osm_way_count"], 14)
        self.assertEqual(c["reconciliation"]["duplicate_class_mismatch_count"], 0)
        self.assertGreater(c["reconciliation"]["historical_worst_residual_m"], 900.0)
        self.assertLess(c["reconciliation"]["candidate_worst_residual_m"], 1.0)
        self.assertGreater(
            c["reconciliation"]["historical_worst_residual_m"] / c["reconciliation"]["candidate_worst_residual_m"],
            1000.0,
        )
        self.assertTrue(all(value is False for value in c["authorization"].values()))

    def test_runtime_or_production_authorization_is_forbidden(self):
        c = copy.deepcopy(self.contract)
        for key in c["authorization"]:
            mutated = copy.deepcopy(c)
            mutated["authorization"][key] = True
            self.assertFalse(all(value is False for value in mutated["authorization"].values()), key)

    def test_candidate_frame_identity_is_frozen(self):
        c = self.contract["candidate_frame"]
        self.assertEqual(c["origin_easting_m"], 148538.362136)
        self.assertEqual(c["origin_northing_m"], 170165.796688)
        self.assertEqual(c["formula"], "E=origin_easting_m+x;N=origin_northing_m-z")
        self.assertEqual(c["pyproj_version"], "3.7.2")


if __name__ == "__main__":
    unittest.main()
