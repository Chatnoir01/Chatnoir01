#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools/qa/reconcile_osm_road_extension_candidate.py"
spec = importlib.util.spec_from_file_location("road_reconcile", SCRIPT)
assert spec and spec.loader
mod = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = mod
spec.loader.exec_module(mod)


class OsmRoadExtensionReconciliationTest(unittest.TestCase):
    def test_forward_and_reverse_exactness(self) -> None:
        source = [(1.0, 2.0), (3.0, 4.0), (5.0, 6.0)]
        forward = mod.compare_sequences(source, [(1.0004, 2.0004), (3.0004, 4.0004), (5.0004, 6.0004)])
        self.assertTrue(forward["exact_sequence_3dp"])
        self.assertEqual(forward["exact_orientation"], "forward")
        reverse = mod.compare_sequences(source, list(reversed(source)))
        self.assertTrue(reverse["exact_sequence_3dp"])
        self.assertEqual(reverse["exact_orientation"], "reverse")

    def test_rigid_offset_is_measured_not_accepted(self) -> None:
        source = [(0.0, 0.0), (10.0, 0.0), (20.0, 0.0)]
        shifted = [(650.0, -12.0), (660.0, -12.0), (670.0, -12.0)]
        result = mod.compare_sequences(source, shifted)
        self.assertFalse(result["exact_sequence_3dp"])
        best = result["best_correspondence"]
        self.assertEqual(best["mean_delta_x_m"], 650.0)
        self.assertEqual(best["mean_delta_z_m"], -12.0)
        self.assertEqual(best["max_rigid_delta_deviation_m"], 0.0)
        self.assertGreater(best["max_corresponding_residual_m"], 600.0)

    def test_node_count_change_remains_explicit(self) -> None:
        source = [(0.0, 0.0), (10.0, 0.0)]
        candidate = [(0.0, 0.0), (5.0, 0.0), (10.0, 0.0)]
        result = mod.compare_sequences(source, candidate)
        self.assertFalse(result["same_count"])
        self.assertIsNone(result["best_correspondence"])
        self.assertEqual(result["source_point_count"], 2)
        self.assertEqual(result["candidate_point_count"], 3)

    def test_authorization_is_fully_closed(self) -> None:
        self.assertTrue(mod.CLOSED_AUTHORIZATION)
        self.assertTrue(all(value is False for value in mod.CLOSED_AUTHORIZATION.values()))
        self.assertIn("source_merge_authorized", mod.CLOSED_AUTHORIZATION)
        self.assertIn("jouable_promotion_authorized", mod.CLOSED_AUTHORIZATION)


if __name__ == "__main__":
    unittest.main()
