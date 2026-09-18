from pathlib import Path
import unittest

RUNTIME = Path(__file__).resolve().parents[1] / "game" / "scripts" / "anneessens_midi_sidewalk_runtime.gd"


class AnneessensMidiSidewalkProvenanceContract(unittest.TestCase):
    def test_unverified_rendered_roads_do_not_claim_source_backed_alignment(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")
        self.assertNotIn('set_meta("road_alignment_source_backed", true)', text)
        self.assertIn('node.set_meta("road_alignment_source_backed", false)', text)
        self.assertIn('node.set_meta("road_alignment_provenance_status", "unverified_rendered_road")', text)
        self.assertIn("_apply_proxy_contract(_root)", text)
        self.assertIn("_apply_proxy_contract(pavement)", text)

    def test_visual_geometry_contract_is_untouched_while_collision_fails_closed(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")
        self.assertIn("_add_sidewalk_pair(road, material)", text)
        self.assertIn("pavement.global_position = road.global_position + lateral * offset * side", text)
        self.assertIn("pavement.global_rotation = road.global_rotation", text)
        # Collision must fail closed both at creation and when visibility is toggled.
        # Do not require duplicate spelling of the same assignment: the toggle path
        # operates through the typed child cast rather than the local pavement name.
        self.assertIn("pavement.use_collision = false", text)
        self.assertIn("(child as CSGBox3D).use_collision = false", text)
        self.assertNotIn("pavement.use_collision = _sidewalks_enabled", text)
        self.assertIn('node.set_meta("collision_source_backed", false)', text)
        self.assertIn('node.set_meta("collision_authorized", false)', text)
        self.assertIn('node.set_meta("collision_policy", "disabled_until_source_backed_vertical_profile")', text)

    def test_empty_generated_roads_releases_false_binding_for_event_driven_retry(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")
        self.assertIn("func _build_from_existing_osm_roads() -> bool:", text)
        self.assertIn("return _sidewalk_count > 0", text)
        self.assertIn("if not _build_from_existing_osm_roads():", text)
        empty_build = text.split("if not _build_from_existing_osm_roads():", 1)[1].split("if manual:", 1)[0]
        self.assertIn("_release_owned_root()", empty_build)
        self.assertIn("_scene = null", empty_build)
        self.assertIn("_manual_binding = false", empty_build)
        self.assertIn("_start_watching()", empty_build)
        # Empty authoritative scenes must not self-reschedule forever. Recovery is
        # event-driven by the retained SceneTree.node_added watcher when roads arrive.
        self.assertNotIn("_schedule_bind()", empty_build)
        self.assertIn("func _on_node_added(node: Node) -> void:", text)
        node_added = text.split("func _on_node_added(node: Node) -> void:", 1)[1].split("func ", 1)[0]
        self.assertIn("_schedule_bind()", node_added)


if __name__ == "__main__":
    unittest.main()
