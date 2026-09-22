from pathlib import Path
import unittest

RUNTIME = Path(__file__).resolve().parents[1] / "game" / "scripts" / "anneessens_midi_sidewalk_runtime.gd"


def _function_block(text: str, name: str) -> str:
    marker = f"func {name}"
    start = text.index(marker)
    next_func = text.find("\nfunc ", start + len(marker))
    return text[start:] if next_func == -1 else text[start:next_func]


class AnneessensMidiSidewalkMutationPollContract(unittest.TestCase):
    """Keep road mutation observation bounded, deterministic, and fail-closed."""

    def test_mutation_observation_uses_one_bounded_poll_path(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")
        self.assertIn("const MUTATION_POLL_SECONDS := 0.25", text)
        self.assertIn("_alignment_road_transforms", text)
        self.assertIn("_alignment_road_sizes", text)
        self.assertIn("_poll_alignment_road_mutations", text)
        self.assertNotIn("road.set_notify_transform(true)", text)
        self.assertNotIn("road.transform_changed.connect", text)
        self.assertNotIn("road.transform_changed.disconnect", text)

    def test_poll_owns_transform_and_size_comparison_and_cleanup_is_signal_free(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")
        poll = _function_block(text, "_poll_alignment_road_mutations(")
        callback = _function_block(text, "_on_alignment_road_mutated(")
        cleanup = _function_block(text, "_disconnect_alignment_road_mutation_watches(")
        stop_timer = _function_block(text, "_stop_mutation_poll_timer(")
        watch = _function_block(text, "_watch_alignment_road_mutations(")
        self.assertIn("_on_alignment_road_mutated(instance_id)", poll)
        self.assertIn("road.global_transform", callback)
        self.assertIn("road.size", callback)
        self.assertNotIn("transform_changed", watch)
        self.assertNotIn("transform_changed", cleanup)
        self.assertIn("_stop_mutation_poll_timer()", cleanup)
        self.assertIn("_mutation_poll_timer.stop()", stop_timer)
        self.assertIn("_alignment_road_refs.clear()", cleanup)
        self.assertIn("_alignment_road_transforms.clear()", cleanup)
        self.assertIn("_alignment_road_sizes.clear()", cleanup)

    def test_poll_avoids_typed_dictionary_key_iteration_and_guards_cast(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")
        poll = _function_block(text, "_poll_alignment_road_mutations(")
        callback = _function_block(text, "_on_alignment_road_mutated(")
        self.assertIn("for instance_id in _alignment_road_refs.keys():", poll)
        self.assertNotIn("for instance_id: Variant in", poll)
        self.assertIn("var road: CSGBox3D = road_ref as CSGBox3D", callback)
        self.assertIn("if road == null:", callback)

    def test_mutation_comparisons_are_explicitly_bool_typed_for_godot_47(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")
        callback = _function_block(text, "_on_alignment_road_mutated(")
        self.assertIn("var did_transform_change: bool = not _alignment_road_transforms.has(instance_id) or road.global_transform != _alignment_road_transforms[instance_id]", callback)
        self.assertIn("var size_changed: bool = not _alignment_road_sizes.has(instance_id) or road.size != _alignment_road_sizes[instance_id]", callback)
        self.assertNotIn("var did_transform_change :=", callback)
        self.assertNotIn("var size_changed :=", callback)

    def test_invalid_watched_road_reference_invalidates_binding_fail_closed(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")
        callback = _function_block(text, "_on_alignment_road_mutated(")
        invalid_ref_guard = callback.index("if not is_instance_valid(road_ref):")
        reset = callback.index("_reset_scene_binding()", invalid_ref_guard)
        restart = callback.index("_start_watching()", reset)
        rebind = callback.index("_schedule_bind()", restart)
        next_cast = callback.index("var road: CSGBox3D", invalid_ref_guard)
        self.assertLess(invalid_ref_guard, reset)
        self.assertLess(reset, restart)
        self.assertLess(restart, rebind)
        self.assertLess(rebind, next_cast)

    def test_wrong_type_watched_reference_invalidates_binding_fail_closed(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")
        callback = _function_block(text, "_on_alignment_road_mutated(")
        cast = callback.index("var road: CSGBox3D = road_ref as CSGBox3D")
        null_guard = callback.index("if road == null:", cast)
        reset = callback.index("_reset_scene_binding()", null_guard)
        restart = callback.index("_start_watching()", reset)
        rebind = callback.index("_schedule_bind()", restart)
        self.assertLess(cast, null_guard)
        self.assertLess(null_guard, reset)
        self.assertLess(reset, restart)
        self.assertLess(restart, rebind)

    def test_manual_binding_never_allocates_or_starts_mutation_timer(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")
        watch = _function_block(text, "_watch_alignment_road_mutations(")
        bind = _function_block(text, "_bind_scene(")
        self.assertNotIn("_ensure_mutation_poll_timer()", watch)
        manual_branch = bind.index("if manual:")
        else_branch = bind.index("else:", manual_branch)
        self.assertNotIn("_ensure_mutation_poll_timer()", bind[manual_branch:else_branch])
        self.assertIn("_ensure_mutation_poll_timer()", bind[else_branch:])

    def test_watched_road_name_identity_mutation_invalidates_binding_fail_closed(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")
        self.assertIn("_alignment_road_names", text)
        watch = _function_block(text, "_watch_alignment_road_mutations(")
        callback = _function_block(text, "_on_alignment_road_mutated(")
        cleanup = _function_block(text, "_disconnect_alignment_road_mutation_watches(")
        self.assertIn("_alignment_road_names[instance_id] = road.name", watch)
        self.assertIn("var name_changed: bool = not _alignment_road_names.has(instance_id) or road.name != _alignment_road_names[instance_id]", callback)
        self.assertIn("if name_changed:", callback)
        name_guard = callback.index("if name_changed:")
        reset = callback.index("_reset_scene_binding()", name_guard)
        restart = callback.index("_start_watching()", reset)
        rebind = callback.index("_schedule_bind()", restart)
        self.assertLess(name_guard, reset)
        self.assertLess(reset, restart)
        self.assertLess(restart, rebind)
        self.assertIn("_alignment_road_names.clear()", cleanup)


if __name__ == "__main__":
    unittest.main()
