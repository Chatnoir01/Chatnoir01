from pathlib import Path
import unittest

RUNTIME = Path(__file__).resolve().parents[1] / "game" / "scripts" / "anneessens_midi_sidewalk_runtime.gd"


class AnneessensMidiSidewalkProvenanceContract(unittest.TestCase):
    def test_unverified_rendered_roads_do_not_claim_source_backed_alignment(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")
        self.assertNotIn(
            'set_meta("road_alignment_source_backed", true)',
            text,
            "Rendered Road_* nodes are not accompanied by an exact provenance contract; "
            "the sidewalk kit must fail closed rather than manufacture a source-backed claim.",
        )
        self.assertGreaterEqual(
            text.count('set_meta("road_alignment_source_backed", false)'),
            2,
            "Both the kit root and generated pavement pieces must expose the fail-closed provenance verdict.",
        )
        self.assertIn(
            'set_meta("road_alignment_provenance_status", "unverified_rendered_road")',
            text,
            "The runtime must make the reason for the fail-closed verdict explicit.",
        )

    def test_visual_geometry_contract_is_untouched(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")
        self.assertIn("_add_sidewalk_pair(road, material)", text)
        self.assertIn("pavement.use_collision = _sidewalks_enabled", text)
        self.assertIn("pavement.global_position = road.global_position + lateral * offset * side", text)
        self.assertIn("pavement.global_rotation = road.global_rotation", text)


if __name__ == "__main__":
    unittest.main()
