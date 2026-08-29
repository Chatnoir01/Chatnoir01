import importlib.util
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).resolve().parents[1] / "tools" / "select_ixelles_runtime_height_candidates.py"
spec = importlib.util.spec_from_file_location("select_ixelles_runtime_height_candidates", MODULE_PATH)
module = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(module)


def row(
    building_id="b1",
    cell_id="cell-a",
    confidence="high",
    p50="10.0",
    p75="12.0",
    p90="14.0",
    plausible_fraction="1.0",
    plausible_pixels="100",
    valid_pixels="100",
    terrain="80.0",
    negative="0",
    over="0",
):
    return {
        "building_id": building_id,
        "cell_id": cell_id,
        "confidence": confidence,
        "height_p50_m": p50,
        "height_p75_m": p75,
        "height_p90_m": p90,
        "plausible_fraction_of_valid": plausible_fraction,
        "pixel_count_plausible": plausible_pixels,
        "pixel_count_valid": valid_pixels,
        "terrain_elevation_m_p50": terrain,
        "negative_below_noise_count": negative,
        "over_250m_count": over,
    }


class RuntimeHeightCandidatePolicyTests(unittest.TestCase):
    def test_high_confidence_uses_p75_but_never_runtime_approves(self):
        candidate = module.candidate_from_row(row(confidence="high", p50="9", p75="12", p90="16"))
        self.assertEqual(candidate["height_candidate_m"], 12.0)
        self.assertEqual(candidate["height_candidate_percentile"], "p75")
        self.assertTrue(candidate["requires_secondary_validation"])
        self.assertFalse(candidate["runtime_approved"])

    def test_medium_confidence_uses_conservative_p50(self):
        candidate = module.candidate_from_row(row(confidence="medium", p50="8", p75="11", p90="15"))
        self.assertEqual(candidate["height_candidate_m"], 8.0)
        self.assertEqual(candidate["height_candidate_percentile"], "p50")
        self.assertFalse(candidate["runtime_approved"])

    def test_insufficient_evidence_emits_no_height(self):
        candidate = module.candidate_from_row(row(confidence="insufficient", p50="", p75="", p90=""))
        self.assertIsNone(candidate["height_candidate_m"])
        self.assertFalse(candidate["requires_secondary_validation"])
        self.assertFalse(candidate["runtime_approved"])

    def test_duplicate_membership_selects_strongest_evidence_deterministically(self):
        rows = [
            row(building_id="same", cell_id="cell-a", confidence="medium", plausible_fraction="0.8", plausible_pixels="40"),
            row(building_id="same", cell_id="cell-b", confidence="high", plausible_fraction="0.95", plausible_pixels="80", p75="13"),
            row(building_id="other", cell_id="cell-c", confidence="high"),
        ]
        result = module.build_candidates(rows)
        self.assertEqual(result["unique_buildings"], 2)
        self.assertEqual(result["duplicate_memberships_removed"], 1)
        same = next(c for c in result["candidates"] if c["building_id"] == "same")
        self.assertEqual(same["source_cell_id"], "cell-b")
        self.assertEqual(same["height_candidate_m"], 13.0)
        self.assertFalse(result["runtime_approved"])

    def test_non_monotonic_quantiles_are_rejected(self):
        with self.assertRaises(ValueError):
            module.candidate_from_row(row(p50="15", p75="12", p90="16"))

    def test_large_roof_spread_is_flagged_for_secondary_review(self):
        candidate = module.candidate_from_row(row(p50="5", p75="10", p90="20"))
        self.assertIn("large_p50_p90_spread_requires_manual_or_secondary_review", candidate["review_flags"])

    def test_negative_and_extreme_samples_are_flagged(self):
        candidate = module.candidate_from_row(row(negative="3", over="1"))
        self.assertIn("negative_dsm_dtm_samples_present", candidate["review_flags"])
        self.assertIn("over_250m_samples_present", candidate["review_flags"])


if __name__ == "__main__":
    unittest.main()
