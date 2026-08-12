import importlib.util
import sys
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).parents[1] / "tools" / "validate_branch_hygiene.py"
SPEC = importlib.util.spec_from_file_location("validate_branch_hygiene", MODULE_PATH)
assert SPEC and SPEC.loader
MOD = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MOD
SPEC.loader.exec_module(MOD)

class BranchHygieneTests(unittest.TestCase):
    def test_rejects_specialist_on_specialist_base(self):
        result = MOD.check("systems-npc-police-civilians", "zone-laeken-jette", [])
        self.assertFalse(result.ok)
        self.assertTrue(any("must target main" in error for error in result.errors))

    def test_rejects_geographic_main_scene_edit(self):
        result = MOD.check("zone-laeken-jette", "main", ["grand-bruxelles-game/game/main.tscn"])
        self.assertFalse(result.ok)

    def test_rejects_contaminated_geographic_gameplay(self):
        result = MOD.check("zone-reste-bruxelles-clean", "main", ["grand-bruxelles-game/game/scripts/traffic_manager.gd"])
        self.assertFalse(result.ok)

    def test_quarantines_long_lived_specialist(self):
        result = MOD.check("zone-laeken-jette", "main", [], ahead=428, behind=0)
        self.assertFalse(result.ok)
        self.assertTrue(any("extract a coherent lot" in error for error in result.errors))

    def test_accepts_small_clean_integration_lot(self):
        result = MOD.check("integration/photo-match-qa-v2", "main", ["grand-bruxelles-game/tools/foo.py"], ahead=3, behind=0)
        self.assertTrue(result.ok)

    def test_rejects_stale_integration_lot(self):
        result = MOD.check("integration/npc-recovery", "main", ["grand-bruxelles-game/game/scripts/npc_agent.gd"], ahead=1, behind=1)
        self.assertFalse(result.ok)
        self.assertTrue(any("behind main" in error for error in result.errors))

    def test_rejects_oversized_integration_lot(self):
        result = MOD.check("integration/shared-core-bundle", "main", ["grand-bruxelles-game/game/scripts/foo.gd"], ahead=21, behind=0)
        self.assertFalse(result.ok)
        self.assertTrue(any("smaller coherent promotion lots" in error for error in result.errors))

if __name__ == "__main__":
    unittest.main()
