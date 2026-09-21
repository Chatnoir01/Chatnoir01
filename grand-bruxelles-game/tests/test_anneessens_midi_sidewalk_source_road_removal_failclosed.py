from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "game" / "scripts" / "anneessens_midi_sidewalk_runtime.gd"


def _function_block(text: str, name: str) -> str:
    marker = f"func {name}"
    start = text.index(marker)
    next_func = text.find("\nfunc ", start + len(marker))
    return text[start:] if next_func == -1 else text[start:next_func]


class AnneessensMidiSidewalkSourceRoadRemovalFailClosedTest(unittest.TestCase):
    def test_consumed_road_instances_are_tracked_and_invalidated(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")
        build_block = _function_block(text, "_build_from_existing_osm_roads(")
        remove_block = _function_block(text, "_on_node_removed(")
        release_block = _function_block(text, "_release_owned_root(")

        self.assertIn("var _alignment_road_instance_ids", text)
        self.assertIn("_alignment_road_instance_ids[road.get_instance_id()] = true", build_block)
        self.assertIn("_alignment_road_instance_ids.has(node.get_instance_id())", remove_block)
        self.assertIn("_reset_scene_binding()", remove_block)
        self.assertIn("_start_watching()", remove_block)
        self.assertIn("_schedule_bind()", remove_block)
        self.assertIn("_alignment_road_instance_ids.clear()", release_block)

    def test_unrelated_node_removal_does_not_rebind(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")
        remove_block = _function_block(text, "_on_node_removed(")
        self.assertIn("node == _scene", remove_block)
        self.assertIn("_alignment_road_instance_ids.has(node.get_instance_id())", remove_block)
        self.assertNotIn("node.name.begins_with(\"Road_\")", remove_block)


if __name__ == "__main__":
    unittest.main()
