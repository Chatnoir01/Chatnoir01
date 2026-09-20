from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "game" / "scripts" / "anneessens_midi_sidewalk_runtime.gd"


class AnneessensMidiSidewalkRoadWitnessFailClosedTest(unittest.TestCase):
    def test_alignment_is_explicitly_unverified_and_non_source_backed(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")

        self.assertIn(
            'const ALIGNMENT_REFERENCE := "rendered GeneratedRoads nodes (unverified source identity)"',
            text,
        )
        self.assertIn(
            'const PROXY_RECIPE := "authored_midi_sidewalk_proxy_from_unverified_rendered_road_alignment"',
            text,
        )
        self.assertIn('target.set_meta("road_alignment_source_backed", false)', text)
        self.assertIn(
            'target.set_meta("road_alignment_provenance_status", "unverified_rendered_road")',
            text,
        )
        self.assertNotIn('target.set_meta("road_alignment_source_backed", true)', text)

    def test_each_rendered_proxy_keeps_exact_road_geometry_witnesses(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")
        marker = "func _add_sidewalk_pair(road: CSGBox3D, material: Material) -> void:"
        self.assertIn(marker, text)
        body = text[text.index(marker) :]

        # The proxy is derived from the rendered road's live transform/size. Keep
        # those inputs beside the derived placement so later provenance work can
        # audit the exact geometry that was consumed without calling it source truth.
        self.assertIn('pavement.set_meta("alignment_witness_road", road.name)', body)
        self.assertIn('pavement.set_meta("alignment_witness_transform", road.global_transform)', body)
        self.assertIn('pavement.set_meta("alignment_witness_size", road.size)', body)
        self.assertIn('pavement.set_meta("alignment_witness_source_backed", false)', body)
        self.assertIn('pavement.set_meta("placement_witness_global_transform", pavement.global_transform)', body)
        self.assertIn('pavement.set_meta("placement_witness_rendered_size", pavement.size)', body)
        self.assertNotIn('pavement.set_meta("alignment_witness_source_backed", true)', body)

    def test_proxy_does_not_manufacture_source_identity_from_node_name(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")
        marker = "func _add_sidewalk_pair(road: CSGBox3D, material: Material) -> void:"
        body = text[text.index(marker) :]

        self.assertIn('pavement.set_meta("source_road", road.name)', body)
        for forbidden in (
            'source_osm_id',
            'source_feature_id',
            'source_geometry_sha256',
            'source_dataset_sha256',
            'road_alignment_source_backed", true',
        ):
            self.assertNotIn(forbidden, body)


if __name__ == "__main__":
    unittest.main()
