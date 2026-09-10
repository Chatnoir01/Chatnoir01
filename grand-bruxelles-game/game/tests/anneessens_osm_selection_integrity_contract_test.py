from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / "game" / "scripts" / "anneessens_osm_furniture_runtime.gd"


class AnneessensOsmSelectionIntegrityContract(unittest.TestCase):
    def test_runtime_fail_closes_selection_identity_and_stats_drift(self) -> None:
        source = RUNTIME.read_text(encoding="utf-8")
        self.assertIn("func _validate_selection_integrity(data: Dictionary, tree_points: Array) -> Variant:", source)
        self.assertIn('selection.get("osm_ids", null)', source)
        self.assertIn('selection.get("anchor", null)', source)
        self.assertIn('stats.get("tree", null)', source)
        self.assertIn('stats.get("total", null)', source)
        self.assertIn('stats.get("bollard", null)', source)
        self.assertIn('stats.get("street_lamp", null)', source)
        self.assertIn('"selection_osm_ids": selected_ids', source)
        self.assertIn('"selection_anchor": ANNEESSENS', source)
        self.assertIn('_root.set_meta("selection_identity_validated", true)', source)
        self.assertIn('_root.set_meta("selection_tree_count", tree_points.size())', source)


if __name__ == "__main__":
    unittest.main()
