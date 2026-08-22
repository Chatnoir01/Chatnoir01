#!/usr/bin/env python3
import json
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "rendered_main_base_attribution.py"


def fp(tile_lumas, histogram=None):
    tiles = [[v, v, v, v] for v in tile_lumas]
    return {
        "fingerprint": {
            "schema": "grand-bruxelles-rendered-main-v1",
            "width": 160,
            "height": 80,
            "tile_cols": len(tiles),
            "tile_rows": 1,
            "tile_sample_step": 8,
            "tiles_rgbl": tiles,
            "luma_histogram": histogram or [0.5, 0.5],
        }
    }


class RenderedMainBaseAttributionTest(unittest.TestCase):
    def run_case(self, candidate, base, frozen, base_failed=True):
        with tempfile.TemporaryDirectory() as td:
            td = pathlib.Path(td)
            paths = {}
            for name, doc in (("candidate", candidate), ("base", base), ("frozen", frozen)):
                path = td / f"{name}.json"
                path.write_text(json.dumps(doc), encoding="utf-8")
                paths[name] = path
            out = td / "out.json"
            proc = subprocess.run(
                [
                    "python3",
                    str(SCRIPT),
                    str(paths["candidate"]),
                    str(paths["base"]),
                    str(paths["frozen"]),
                    str(out),
                    "base-sha",
                    "head-sha",
                    "1" if base_failed else "0",
                ],
                text=True,
                capture_output=True,
            )
            doc = json.loads(out.read_text()) if out.exists() else None
            return proc, doc

    def test_accepts_head_that_only_improves_inherited_frozen_drift(self):
        frozen = fp([0.10, 0.10])
        base = fp([0.62, 0.36])
        candidate = fp([0.62, 0.16])
        proc, doc = self.run_case(candidate, base, frozen, base_failed=True)
        self.assertEqual(proc.returncode, 0, proc.stderr + proc.stdout)
        self.assertTrue(doc["inherited_frozen_baseline_drift"])
        self.assertGreater(doc["max_improvement_toward_frozen"], 0.19)
        self.assertLessEqual(doc["max_regression_away_from_frozen"], 0.002)

    def test_rejects_new_tile_regression_hidden_by_larger_inherited_drift(self):
        frozen = fp([0.10, 0.10])
        base = fp([0.62, 0.10])
        candidate = fp([0.62, 0.30])
        proc, doc = self.run_case(candidate, base, frozen, base_failed=True)
        self.assertNotEqual(proc.returncode, 0)
        self.assertFalse(doc["inherited_frozen_baseline_drift"])
        self.assertGreater(doc["max_regression_away_from_frozen"], 0.19)

    def test_rejects_attribution_when_exact_base_was_green(self):
        frozen = fp([0.10, 0.10])
        base = fp([0.10, 0.10])
        candidate = fp([0.10, 0.10])
        proc, doc = self.run_case(candidate, base, frozen, base_failed=False)
        self.assertNotEqual(proc.returncode, 0)
        self.assertFalse(doc["inherited_frozen_baseline_drift"])

    def test_rejects_histogram_regression_even_when_tiles_improve(self):
        frozen = fp([0.10], [0.5, 0.5])
        base = fp([0.60], [0.5, 0.5])
        candidate = fp([0.50], [0.54, 0.46])
        proc, doc = self.run_case(candidate, base, frozen, base_failed=True)
        self.assertNotEqual(proc.returncode, 0)
        self.assertFalse(doc["inherited_frozen_baseline_drift"])
        self.assertGreater(doc["max_histogram_regression_away_from_frozen"], 0.03)


if __name__ == "__main__":
    unittest.main()
