import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "data/terrain/ixelles/ixelles_dtm_2m_candidate_evidence.json"

EXPECTED_CELLS = {
    "bxl-e149000-n169000-s500",
    "bxl-e149000-n169500-s500",
    "bxl-e149500-n168500-s500",
    "bxl-e149500-n169000-s500",
    "bxl-e149500-n169500-s500",
}

class IxellesDtm2mCandidateEvidenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = json.loads(EVIDENCE.read_text(encoding="utf-8"))

    def test_exact_locked_source_and_cells(self):
        data = self.data
        self.assertEqual(data["source_crs"], "EPSG:31370")
        self.assertEqual(data["source"]["specialist_lod_blob"], "aa9741161103137841f5e0b789474071773d82d7")
        self.assertEqual(data["source"]["specialist_selection_blob"], "9e20c2bea563db7c98464ddef5bcf65bbde22c06")
        self.assertEqual({c["cell_id"] for c in data["cells"]}, EXPECTED_CELLS)
        self.assertEqual(len(data["cells"]), 5)

    def test_two_metre_selection_meets_only_selection_gate(self):
        data = self.data
        self.assertEqual(data["candidate_resolution_m"], 2.0)
        limit = data["selection_policy"]["p95_vertical_error_limit_m"]
        self.assertLessEqual(max(c["p95_abs_error_m"] for c in data["cells"]), limit)
        self.assertGreater(data["aggregate"]["four_m_worst_cell_p95_abs_error_m"], limit)
        self.assertEqual(data["selection_policy"]["grid_vertices_per_500m_cell"], 62500)
        self.assertEqual(data["selection_policy"]["vertex_reduction_vs_1m"], 4.0)

    def test_runtime_promotion_is_refused_until_runtime_gates_exist(self):
        data = self.data
        self.assertFalse(data["runtime_approved"])
        self.assertFalse(data["promote_runtime"])
        self.assertEqual(len(data["required_runtime_gates"]), 5)
        self.assertEqual(data["status"], "candidate_selection_locked_runtime_validation_not_yet_performed")

if __name__ == "__main__":
    unittest.main()
