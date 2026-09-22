from pathlib import Path
import re
import unittest


RUNTIME = Path(__file__).resolve().parents[1] / "game" / "scripts" / "anneessens_midi_sidewalk_runtime.gd"


class AnneessensMidiSidewalkInvisibleRoadFailClosedTests(unittest.TestCase):
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

    def test_invisible_roads_are_watched_but_never_consumed(self):
        build = self._body("_build_from_existing_osm_roads")
        watch = build.find("_watch_alignment_road_mutations(road)")
        visibility_guard = re.search(r"if\s+not\s+road\.visible\s*:\s*\n\s*continue", build)
        consume = build.find("_alignment_road_instance_ids[road.get_instance_id()] = true")
        self.assertGreaterEqual(watch, 0, "all roads must remain watched for future eligibility transitions")
        self.assertIsNotNone(visibility_guard, "invisible source roads must be excluded fail-closed")
        self.assertLess(watch, visibility_guard.start(), "visibility must be snapshotted before filtering")
        self.assertLess(visibility_guard.start(), consume, "invisible roads must never enter the consumed-road set")


if __name__ == "__main__":
    unittest.main()
