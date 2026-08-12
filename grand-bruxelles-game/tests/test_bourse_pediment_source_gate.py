import importlib.util
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools" / "derive_bourse_pediment_source_gate.py"
spec = importlib.util.spec_from_file_location("bourse_pediment_gate", SCRIPT)
mod = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(mod)


class BoursePedimentSourceGateTest(unittest.TestCase):
    def test_synthetic_triangle_is_detected_but_never_runtime_approved(self):
        points = []
        t_min, t_max = -15.0, 15.0
        for i in range(41):
            t = t_min + (t_max - t_min) * i / 40.0
            y = 21.0 + 5.0 * max(0.0, 1.0 - abs(t) / 15.0)
            points.append({"x_m": 0.0, "y_m": y, "z_m": 0.0, "tangent_m": t, "depth_m": 0.3})
        result = mod.derive_from_projected(points, t_min, t_max, 2.0)
        self.assertTrue(result["defensible"])
        self.assertGreater(result["rise_m"], 1.25)

    def test_flat_profile_is_rejected(self):
        points = [
            {"x_m": 0.0, "y_m": 22.0, "z_m": 0.0, "tangent_m": -15.0 + 30.0 * i / 40.0, "depth_m": 0.2}
            for i in range(41)
        ]
        result = mod.derive_from_projected(points, -15.0, 15.0, 2.0)
        self.assertFalse(result["defensible"])
        self.assertEqual(result["reason"], "front_source_profile_not_uniquely_triangular")

    def test_real_bourse_report_never_auto_approves_runtime(self):
        hero = json.loads((ROOT / "data/urbis/heroes/bourse_lod2.game.json").read_text())
        candidate = json.loads((ROOT / "data/qa/bourse_portico_articulation_candidate.json").read_text())
        report = mod.analyze(hero, candidate)
        self.assertEqual(report["schema"], mod.SCHEMA)
        self.assertEqual(report["hero_id"], "bourse")
        self.assertEqual(report["source"]["crs"], "EPSG:31370")
        self.assertFalse(report["pediment_geometry_approved_for_runtime_overlay"])
        self.assertFalse(report["runtime_approved"])
        self.assertFalse(report["realism_complete"])
        self.assertIn(report["status"], {
            "source_envelope_candidate_found_manual_visual_gate_required",
            "source_profile_insufficient_do_not_invent_pediment",
        })


if __name__ == "__main__":
    unittest.main()
