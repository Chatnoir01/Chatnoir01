#!/usr/bin/env python3
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
RENDERED_BASELINE = ROOT / "game" / "tests" / "rendered_main_baseline_test.gd"


class RenderedMainWarmupRenderPolicyTest(unittest.TestCase):
    def test_warmup_preserves_frame_budget_without_rendering_every_frame(self):
        script = RENDERED_BASELINE.read_text(encoding="utf-8")

        # The evidence budget is frozen: optimize the harness, not the gate.
        self.assertIn("const WARMUP_FRAMES := 120", script)
        self.assertIn("const SAMPLE_FRAMES := 120", script)

        disable = script.index("RenderingServer.render_loop_enabled = false")
        warmup = script.index("for _i: int in range(WARMUP_FRAMES):")
        restore = script.index("RenderingServer.render_loop_enabled = true")
        prime = script.index("RenderingServer.force_draw()", restore)
        sample_clock = script.index("var previous_tick_usec := Time.get_ticks_usec()")
        sample = script.index("for _i: int in range(SAMPLE_FRAMES):")

        self.assertLess(disable, warmup)
        self.assertLess(warmup, restore)
        self.assertLess(restore, prime)
        self.assertLess(prime, sample_clock)
        self.assertLess(sample_clock, sample)

    def test_rendering_is_restored_before_measured_sample(self):
        script = RENDERED_BASELINE.read_text(encoding="utf-8")
        restore = script.index("RenderingServer.render_loop_enabled = true")
        sample = script.index("for _i: int in range(SAMPLE_FRAMES):")
        self.assertLess(restore, sample)


if __name__ == "__main__":
    unittest.main()
