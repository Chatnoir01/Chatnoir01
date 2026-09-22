from pathlib import Path
import unittest

RUNTIME = Path(__file__).resolve().parents[1] / "game" / "scripts" / "anneessens_midi_sidewalk_runtime.gd"


class AnneessensMidiSidewalkRoadMutationContract(unittest.TestCase):
    """Rendered-road witnesses must invalidate stale or newly eligible sidewalk proxies."""

    def test_consumed_roads_watch_transform_and_bound_size_mutation(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")
        self.assertIn("_alignment_road_instance_ids", text)
        self.assertIn("_watch_alignment_road_mutations(road)", text)
        self.assertIn("_alignment_road_transforms", text)
        self.assertIn("road.global_transform", text)
        self.assertNotIn("road.transform_changed", text)
        self.assertNotIn("road.mesh_updated", text)
        self.assertNotIn("road.property_list_changed", text)
        self.assertIn("MUTATION_POLL_SECONDS", text)
        self.assertIn("func _poll_alignment_road_mutations() -> void:", text)
        self.assertIn("_ensure_mutation_poll_timer()", text)
        self.assertIn("_on_alignment_road_mutated(instance_id)", text)

    def test_generated_roads_are_watched_before_detail_radius_filter(self) -> None:
        """A road outside the radius can later move into view and must trigger a rebuild."""
        text = RUNTIME.read_text(encoding="utf-8")
        build = text.split("func _build_from_existing_osm_roads() -> bool:", 1)[1].split("\nfunc ", 1)[0]
        watch = build.index("_watch_alignment_road_mutations(road)")
        radius_filter = build.index("if center_2d.distance_to(ANNEESSENS) > DETAIL_RADIUS_M:")
        self.assertLess(
            watch,
            radius_filter,
            "GeneratedRoads must be snapshotted before the Anneessens radius filter so a road moving into the detail radius invalidates/rebuilds the proxy set.",
        )

    def test_polling_is_bounded_and_stops_when_owned_state_is_released(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")
        self.assertIn("const MUTATION_POLL_SECONDS := 0.25", text)
        self.assertNotIn("func _process(", text)
        disconnect = text.split("func _disconnect_alignment_road_mutation_watches() -> void:", 1)[1].split("\nfunc ", 1)[0]
        stop_timer = text.split("func _stop_mutation_poll_timer() -> void:", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn("_stop_mutation_poll_timer()", disconnect)
        self.assertIn("_mutation_poll_timer.stop()", stop_timer)
        self.assertIn("_alignment_road_transforms.clear()", disconnect)
        self.assertIn("_alignment_road_sizes.clear()", disconnect)

    def test_poll_noise_does_not_rebuild_without_witness_change(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")
        self.assertIn("_alignment_road_transforms[instance_id] = road.global_transform", text)
        self.assertIn("_alignment_road_sizes[instance_id] = road.size", text)
        callback = text.split("func _on_alignment_road_mutated(instance_id: Variant) -> void:", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn("did_transform_change", callback)
        self.assertNotIn("var transform_changed :=", callback)
        self.assertIn("size_changed", callback)
        no_change_guard = callback.index("if not did_transform_change and not size_changed:")
        changed_road_reset = callback.index("_reset_scene_binding()", no_change_guard)
        self.assertLess(no_change_guard, changed_road_reset)

    def test_mutation_watch_is_disconnected_before_owned_state_is_released(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")
        release = text.split("func _release_owned_root() -> void:", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn("_disconnect_alignment_road_mutation_watches()", release)
        self.assertLess(release.index("_disconnect_alignment_road_mutation_watches()"), release.index("_alignment_road_instance_ids.clear()"))

    def test_mutation_rebuild_preserves_non_source_backed_and_collision_closed_contract(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")
        self.assertIn('target.set_meta("road_alignment_source_backed", false)', text)
        self.assertIn('node.set_meta("collision_authorized", false)', text)
        self.assertIn("pavement.use_collision = false", text)
        self.assertNotIn('road_alignment_source_backed", true', text)


if __name__ == "__main__":
    unittest.main()
