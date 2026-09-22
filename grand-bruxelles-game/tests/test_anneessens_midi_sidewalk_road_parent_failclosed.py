from pathlib import Path
import unittest

RUNTIME = Path(__file__).resolve().parents[1] / "game" / "scripts" / "anneessens_midi_sidewalk_runtime.gd"


def _function_block(text: str, name: str) -> str:
    marker = f"func {name}"
    start = text.index(marker)
    next_func = text.find("\nfunc ", start + len(marker))
    return text[start:] if next_func == -1 else text[start:next_func]


class AnneessensMidiSidewalkRoadParentFailClosed(unittest.TestCase):
    """A consumed road must remain a direct GeneratedRoads child while proxies live."""

    def test_reparented_consumed_road_invalidates_binding_fail_closed(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")
        callback = _function_block(text, "_on_alignment_road_mutated(")

        hierarchy_guard = callback.index("if not _is_generated_road_child(road):")
        reset = callback.index("_reset_scene_binding()", hierarchy_guard)
        restart = callback.index("_start_watching()", reset)
        rebind = callback.index("_schedule_bind()", restart)
        transform_compare = callback.index("var did_transform_change: bool", hierarchy_guard)

        self.assertLess(hierarchy_guard, reset)
        self.assertLess(reset, restart)
        self.assertLess(restart, rebind)
        self.assertLess(rebind, transform_compare)

    def test_generated_road_identity_predicate_requires_direct_parent(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")
        predicate = _function_block(text, "_is_generated_road_child(")
        self.assertIn('node.name.begins_with("Road_")', predicate)
        self.assertIn('var roads := _scene.get_node_or_null("BrusselsOSM/GeneratedRoads")', predicate)
        self.assertIn("node.get_parent() == roads", predicate)


if __name__ == "__main__":
    unittest.main()
