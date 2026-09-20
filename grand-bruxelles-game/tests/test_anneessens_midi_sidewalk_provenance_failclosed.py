from pathlib import Path
import unittest

RUNTIME = Path(__file__).resolve().parents[1] / "game" / "scripts" / "anneessens_midi_sidewalk_runtime.gd"


class AnneessensMidiSidewalkProvenanceContract(unittest.TestCase):
    def test_unverified_rendered_roads_do_not_claim_source_backed_alignment(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")
        self.assertNotIn('set_meta("road_alignment_source_backed", true)', text)
        self.assertIn('func _apply_alignment_contract(target: Object) -> void:', text)
        self.assertEqual(text.count('set_meta("road_alignment_source_backed", false)'), 1)
        self.assertEqual(text.count('set_meta("road_alignment_provenance_status", "unverified_rendered_road")'), 1)
        self.assertIn("_apply_alignment_contract(node)", text)
        self.assertIn("_apply_alignment_contract(material)", text)
        self.assertIn("_apply_proxy_contract(_root)", text)
        self.assertIn("_apply_proxy_contract(pavement)", text)

    def test_visual_geometry_contract_is_untouched_while_collision_fails_closed(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")
        self.assertIn("_add_sidewalk_pair(road, material)", text)
        self.assertIn("pavement.global_position = road.global_position + lateral * offset * side", text)
        self.assertIn("pavement.global_rotation = road.global_rotation", text)
        self.assertNotIn("pavement.use_collision = _sidewalks_enabled", text)
        self.assertIn('node.set_meta("collision_source_backed", false)', text)
        self.assertIn('node.set_meta("collision_authorized", false)', text)
        self.assertIn('node.set_meta("collision_policy", "disabled_until_source_backed_vertical_profile")', text)

        add_pair = text.split("func _add_sidewalk_pair(road: CSGBox3D, material: Material) -> void:", 1)[1].split("func diagnostic_sidewalk_count", 1)[0]
        self.assertIn("pavement.use_collision = false", add_pair)
        visibility_toggle = text.split("func set_sidewalks_enabled(enabled: bool) -> void:", 1)[1]
        self.assertIn("pavement.use_collision = false", visibility_toggle)

    def test_empty_generated_roads_preserves_manual_isolation_and_auto_retry(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")
        bind = text.split("func _bind_scene(scene: Node3D, manual: bool) -> void:", 1)[1].split("func _build_from_existing_osm_roads", 1)[0]
        empty_build = bind.split("if not _build_from_existing_osm_roads():", 1)[1].split("        return", 1)[0]
        self.assertIn("_release_owned_root()", empty_build)
        self.assertIn("_scene = null", empty_build)
        self.assertIn("if manual:", empty_build)
        manual_failure = empty_build.split("if manual:", 1)[1].split("else:", 1)[0]
        automatic_failure = empty_build.split("else:", 1)[1]
        self.assertIn("_stop_watching()", manual_failure)
        self.assertNotIn("_manual_binding = false", manual_failure)
        self.assertNotIn("_start_watching()", manual_failure)
        self.assertIn("_manual_binding = false", automatic_failure)
        self.assertIn("_start_watching()", automatic_failure)
        self.assertNotIn("_schedule_bind()", empty_build)
        node_added = text.split("func _on_node_added(_node: Node) -> void:", 1)[1].split("func ", 1)[0]
        self.assertIn("_schedule_bind()", node_added)


if __name__ == "__main__":
    unittest.main()
