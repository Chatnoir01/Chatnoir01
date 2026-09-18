from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "game" / "scripts" / "anneessens_midi_sidewalk_runtime.gd"


class AnneessensMidiSidewalkEmptyRoadsFailClosedTest(unittest.TestCase):
    def test_empty_generated_roads_does_not_commit_scene_binding(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")
        self.assertIn(
            "func _build_from_existing_osm_roads() -> bool:",
            text,
            "Road discovery must report whether any source-aligned proxy was actually built.",
        )
        self.assertIn(
            "if not _build_from_existing_osm_roads():",
            text,
            "Binding must fail closed when GeneratedRoads exists but yields no eligible source roads.",
        )
        self.assertIn(
            "_release_owned_root()",
            text,
            "A failed build must not leave an empty authoritative sidewalk root mounted.",
        )
        self.assertIn(
            "_scene = null",
            text,
            "A failed automatic bind must release scene authority so a later valid scene state can retry.",
        )
        self.assertIn(
            "return _sidewalk_count > 0",
            text,
            "Successful binding must be evidenced by at least one generated proxy, not node presence alone.",
        )


if __name__ == "__main__":
    unittest.main()
