import importlib.util
from pathlib import Path
import unittest

MODULE_PATH = Path(__file__).parents[1] / "tools" / "qa" / "check_gate8_variant01_run_speed_compatibility.py"
spec = importlib.util.spec_from_file_location("run_speed_compat", MODULE_PATH)
mod = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(mod)


class RunSpeedCompatibilityTests(unittest.TestCase):
    def setUp(self):
        self.runtime = {
            "MAX_OBSERVED_SPEED_MPS": 2.4,
            "RUN_ENTER_SPEED_MPS": 1.65,
            "RUN_REFERENCE_SPEED_MPS": 1.85,
            "RUN_PLAYBACK_MIN": 0.82,
            "RUN_PLAYBACK_MAX": 1.22,
        }

    def test_incompatible_when_even_min_playback_exceeds_runtime_max(self):
        row = mod.evaluate_clip(4.71173677841822, self.runtime)
        self.assertFalse(row["compatible_with_current_civilian_run_contract"])
        self.assertGreater(row["minimum_world_speed_for_planted_feet_mps"], 2.4)
        self.assertEqual(row["verdict"], "JETER_CURRENT_CIVILIAN_RUN_CONTRACT")

    def test_compatible_when_speed_intervals_overlap(self):
        row = mod.evaluate_clip(2.0, self.runtime)
        self.assertTrue(row["compatible_with_current_civilian_run_contract"])
        self.assertIsNotNone(row["interval_overlap_mps"])

    def test_runtime_parser_is_fail_closed(self):
        text = "\n".join([
            "const MAX_OBSERVED_SPEED_MPS := 2.4",
            "const RUN_ENTER_SPEED_MPS := 1.65",
            "const RUN_REFERENCE_SPEED_MPS := 1.85",
            "const RUN_PLAYBACK_MIN := 0.82",
        ])
        with self.assertRaisesRegex(ValueError, "missing_runtime_constant:RUN_PLAYBACK_MAX"):
            mod.parse_runtime_constants(text)

    def test_exact_runtime_constants_parse(self):
        text = "\n".join(f"const {k} := {v}" for k, v in self.runtime.items())
        self.assertEqual(mod.parse_runtime_constants(text), self.runtime)


if __name__ == "__main__":
    unittest.main()
