#!/usr/bin/env python3
import json
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "rendered_main_base_attribution.py"
WORKFLOW = ROOT.parent / ".github" / "workflows" / "grand-bruxelles-performance.yml"


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


def fp_tiles(tiles, histogram=None):
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
        self.assertEqual(doc["improved_tile_indexes"], [1])
        self.assertLessEqual(doc["max_regression_away_from_frozen"], 0.002)

    def test_rejects_new_tile_regression_hidden_by_larger_inherited_drift(self):
        frozen = fp([0.10, 0.10])
        base = fp([0.62, 0.10])
        candidate = fp([0.62, 0.30])
        proc, doc = self.run_case(candidate, base, frozen, base_failed=True)
        self.assertNotEqual(proc.returncode, 0)
        self.assertFalse(doc["inherited_frozen_baseline_drift"])
        self.assertEqual(doc["regressed_tile_indexes"], [1])

    def test_rejects_attribution_when_exact_base_was_green(self):
        frozen = fp([0.10, 0.10])
        base = fp([0.10, 0.10])
        candidate = fp([0.10, 0.10])
        proc, doc = self.run_case(candidate, base, frozen, base_failed=False)
        self.assertNotEqual(proc.returncode, 0)
        self.assertFalse(doc["inherited_frozen_baseline_drift"])

    def test_rejects_histogram_mae_regression_even_when_tiles_improve(self):
        frozen = fp([0.10], [0.5, 0.5])
        base = fp([0.60], [0.5, 0.5])
        candidate = fp([0.50], [0.54, 0.46])
        proc, doc = self.run_case(candidate, base, frozen, base_failed=True)
        self.assertNotEqual(proc.returncode, 0)
        self.assertFalse(doc["inherited_frozen_baseline_drift"])
        self.assertIn("luma_histogram_mae", doc["aggregate_regressions"])

    def test_accepts_rgb_channel_noise_when_official_tile_metrics_improve(self):
        frozen = fp_tiles([[0.20, 0.20, 0.20, 0.20]])
        base = fp_tiles([[0.50, 0.20, 0.50, 0.40]])
        candidate = fp_tiles([[0.25, 0.21, 0.25, 0.25]])
        proc, doc = self.run_case(candidate, base, frozen, base_failed=True)
        self.assertEqual(proc.returncode, 0, proc.stderr + proc.stdout)
        self.assertTrue(doc["monotonic_toward_frozen"])
        self.assertEqual(doc["improved_tile_indexes"], [0])
        self.assertLess(doc["candidate_frozen_metrics"]["tile_rgb_mae"], doc["base_frozen_metrics"]["tile_rgb_mae"])

    def test_rejects_equal_distance_visual_swap(self):
        frozen = fp([0.50])
        base = fp([0.30])
        candidate = fp([0.70])
        proc, doc = self.run_case(candidate, base, frozen, base_failed=True)
        self.assertNotEqual(proc.returncode, 0)
        self.assertFalse(doc["monotonic_toward_frozen"])
        self.assertEqual(doc["regressed_tile_indexes"], [0])

    def test_accepts_histogram_bin_noise_when_histogram_mae_improves(self):
        tiles = [[0.40, 0.40, 0.40, 0.40]]
        frozen = fp_tiles(tiles, [0.25, 0.25, 0.25, 0.25])
        base = fp_tiles(tiles, [0.15, 0.35, 0.25, 0.25])
        candidate = fp_tiles(tiles, [0.14, 0.30, 0.26, 0.25])
        proc, doc = self.run_case(candidate, base, frozen, base_failed=True)
        self.assertEqual(proc.returncode, 0, proc.stderr + proc.stdout)
        self.assertTrue(doc["monotonic_toward_frozen"])
        self.assertLess(
            doc["candidate_frozen_metrics"]["luma_histogram_mae"],
            doc["base_frozen_metrics"]["luma_histogram_mae"],
        )

    def test_small_renderer_noise_stays_within_existing_attribution_tolerance(self):
        frozen = fp([0.10])
        base = fp([0.30])
        candidate = fp([0.301])
        proc, doc = self.run_case(candidate, base, frozen, base_failed=True)
        self.assertEqual(proc.returncode, 0, proc.stderr + proc.stdout)
        self.assertTrue(doc["monotonic_toward_frozen"])
        self.assertEqual(doc["changed_tile_indexes"], [])

    def test_workflow_requires_explicit_visual_guard_failures_for_attribution(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("VISUAL_GUARD_PATTERN=", workflow)
        self.assertIn('grep -Eq "$VISUAL_GUARD_PATTERN" /tmp/rendered-main-baseline.log', workflow)
        self.assertIn('grep -Eq "$VISUAL_GUARD_PATTERN" /tmp/rendered-base-baseline.log', workflow)

    def test_workflow_retries_both_godot_release_downloads(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        download_url = "https://github.com/godotengine/godot-builds/releases/download/4.7.1-stable/Godot_v4.7.1-stable_linux.x86_64.zip"
        install_blocks = workflow.split("- name: Install Godot 4.7.1")[1:]
        self.assertEqual(len(install_blocks), 2)
        for block in install_blocks:
            self.assertIn(download_url, block)
            self.assertIn("--retry 4", block)
            self.assertIn("--retry-all-errors", block)
            self.assertIn("--retry-delay 2", block)


if __name__ == "__main__":
    unittest.main()
