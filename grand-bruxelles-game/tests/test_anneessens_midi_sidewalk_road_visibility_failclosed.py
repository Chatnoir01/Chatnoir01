from pathlib import Path
import re
import unittest


RUNTIME = Path(__file__).resolve().parents[1] / "game" / "scripts" / "anneessens_midi_sidewalk_runtime.gd"


class AnneessensMidiSidewalkRoadVisibilityFailClosedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = RUNTIME.read_text(encoding="utf-8")

    def _body(self, function_name: str) -> str:
        match = re.search(
            rf"(?ms)^func {re.escape(function_name)}\([^\n]*\).*?(?=^func |\Z)",
            self.source,
        )
        self.assertIsNotNone(match, f"missing {function_name}")
        return match.group(0)

    def test_visibility_is_snapshotted_for_every_watched_road(self):
        self.assertRegex(
            self.source,
            r"var\s+_alignment_road_visibilities\s*:\s*Dictionary\s*=\s*\{\}",
            "road visibility needs an explicit witness snapshot",
        )
        watch = self._body("_watch_alignment_road_mutations")
        self.assertRegex(
            watch,
            r"_alignment_road_visibilities\s*\[\s*instance_id\s*\]\s*=\s*road\.visible",
            "every watched GeneratedRoad must snapshot visibility before eligibility filters",
        )

    def test_visibility_change_invalidates_binding_fail_closed(self):
        mutated = self._body("_on_alignment_road_mutated")
        self.assertRegex(
            mutated,
            r"(?:visibility_changed|did_visibility_change)\s*:\s*bool\s*=.*road\.visible.*_alignment_road_visibilities\s*\[\s*instance_id\s*\]",
            "mutation polling must compare current road visibility with the bound witness",
        )
        self.assertRegex(
            mutated,
            r"if\s+.*(?:visibility_changed|did_visibility_change).*:\s*\n\s*_reset_scene_binding\(\)\s*\n\s*_start_watching\(\)\s*\n\s*_schedule_bind\(\)",
            "a visibility mutation must drop derived proxies and schedule a clean rebind",
        )

    def test_visibility_witness_is_cleared_with_other_road_snapshots(self):
        disconnect = self._body("_disconnect_alignment_road_mutation_watches")
        self.assertIn("_alignment_road_visibilities.clear()", disconnect)


if __name__ == "__main__":
    unittest.main()
