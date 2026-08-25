import importlib.util
from pathlib import Path
import unittest

MODULE_PATH = Path(__file__).parents[1] / "tools" / "qa" / "check_gate8_variant01_walk_speed_compatibility.py"
spec = importlib.util.spec_from_file_location("walk_speed_compat", MODULE_PATH)
mod = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(mod)


class WalkSpeedCompatibilityTests(unittest.TestCase):
    def setUp(self):
        self.runtime = {
            "IDLE_EXIT_SPEED_MPS": 0.20,
            "RUN_ENTER_SPEED_MPS": 1.65,
            "WALK_REFERENCE_SPEED_MPS": 1.0,
            "WALK_PLAYBACK_MIN": 0.68,
            "WALK_PLAYBACK_MAX": 1.45,
        }

    def test_walk_reaches_reference_inside_playback_window(self):
        required_root_speed = 0.9053650
        row = mod.evaluate_clip("Walk", required_root_speed, self.runtime, "normal_walk")
        self.assertTrue(row["compatible_with_current_civilian_walk_speed_contract"])
        self.assertAlmostEqual(
            row["ideal_playback_at_walk_reference"],
            self.runtime["WALK_REFERENCE_SPEED_MPS"] / required_root_speed,
            places=12,
        )

    def test_formal_walk_is_also_speed_compatible(self):
        row = mod.evaluate_clip("Walk_Formal", 0.9349154, self.runtime, "normal_walk")
        self.assertTrue(row["compatible_with_current_civilian_walk_speed_contract"])
        self.assertLess(row["ideal_playback_at_walk_reference"], 1.45)

    def test_crouch_is_not_repurposed_as_normal_walk(self):
        row = mod.evaluate_clip("Crouch_Fwd", 0.5915679, self.runtime, "crouch_only")
        self.assertFalse(row["compatible_with_current_civilian_walk_speed_contract"])
        self.assertFalse(row["walk_reference_reachable_with_allowed_playback"])
        self.assertEqual(row["verdict"], "JETER_CURRENT_NORMAL_WALK_CONTRACT")

    def test_runtime_parser_fails_closed_on_missing_constant(self):
        text = "\n".join([
            "const IDLE_EXIT_SPEED_MPS := 0.20",
            "const RUN_ENTER_SPEED_MPS := 1.65",
            "const WALK_REFERENCE_SPEED_MPS := 1.0",
            "const WALK_PLAYBACK_MIN := 0.68",
        ])
        with self.assertRaisesRegex(ValueError, "missing_runtime_constant:WALK_PLAYBACK_MAX"):
            mod.parse_runtime_constants(text)

    def test_runtime_contract_drift_is_rejected(self):
        manifest = {
            "candidate_variant": 1,
            "runtime_contract": {"expected": self.runtime},
            "source_scan_proof": {
                "run_id": 1, "artifact_id": 2, "artifact_digest": "sha256:x",
                "required_root_speed_mean_mps": {"Walk": 0.9053650},
                "contact_slide_peak_mps": {"Walk": 1.2}
            },
            "semantic_roles": {"Walk": "normal_walk"}
        }
        drift = dict(self.runtime); drift["RUN_ENTER_SPEED_MPS"] = 1.70
        text = "\n".join(f"const {k} := {v}" for k, v in drift.items())
        with self.assertRaisesRegex(ValueError, "runtime_contract_drift:RUN_ENTER_SPEED_MPS"):
            mod.evaluate(manifest, text)


if __name__ == "__main__":
    unittest.main()
