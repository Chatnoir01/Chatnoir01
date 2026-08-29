import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REFS = ROOT / "data/processed/remaining_brussels/references"


class IxellesDtmRuntimeSelectionTests(unittest.TestCase):
    def test_selection_is_coarsest_candidate_under_realism_threshold(self):
        evidence = json.loads((REFS / "ixelles_dtm_lod_evidence.json").read_text(encoding="utf-8"))
        selection = json.loads((REFS / "ixelles_dtm_runtime_selection.json").read_text(encoding="utf-8"))
        self.assertEqual(evidence["source_crs"], "EPSG:31370")
        self.assertFalse(selection["runtime_approved"])
        threshold = 0.15
        eligible = []
        for resolution in evidence["candidate_resolutions_m"]:
            worst = max(
                next(level for level in cell["levels"] if level["resolution_m"] == resolution)["p95_abs_error_m"]
                for cell in evidence["cells"]
            )
            if worst <= threshold:
                eligible.append(resolution)
        self.assertTrue(eligible)
        self.assertEqual(selection["selected_resolution_m"], max(eligible))
        self.assertEqual(selection["selected_resolution_m"], 2.0)
        four_m_worst = max(
            next(level for level in cell["levels"] if level["resolution_m"] == 4.0)["p95_abs_error_m"]
            for cell in evidence["cells"]
        )
        self.assertGreater(four_m_worst, threshold)

    def test_all_cells_retain_official_half_metre_source(self):
        evidence = json.loads((REFS / "ixelles_dtm_lod_evidence.json").read_text(encoding="utf-8"))
        self.assertEqual(len(evidence["cells"]), 5)
        for cell in evidence["cells"]:
            self.assertEqual(cell["source_pixel_size_m"], 0.5)
            self.assertEqual([level["resolution_m"] for level in cell["levels"]], [1.0, 2.0, 4.0, 8.0])
            self.assertTrue(all(level["paired_samples"] > 900000 for level in cell["levels"]))


if __name__ == "__main__":
    unittest.main()
