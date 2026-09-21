from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "game" / "scripts" / "anneessens_midi_sidewalk_runtime.gd"


def _function_block(text: str, name: str) -> str:
    marker = f"func {name}"
    start = text.index(marker)
    next_func = text.find("\nfunc ", start + len(marker))
    return text[start:] if next_func == -1 else text[start:next_func]


class AnneessensMidiSidewalkSourceRoadAdditionFailClosedTest(unittest.TestCase):
    def test_generated_road_addition_invalidates_and_rebinds(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")
        helper = _function_block(text, "_is_generated_road_child(")
        added = _function_block(text, "_on_node_added(")

        self.assertIn('node is CSGBox3D', helper)
        self.assertIn('node.name.begins_with("Road_")', helper)
        self.assertIn('BrusselsOSM/GeneratedRoads', helper)
        self.assertIn('node.get_parent() == roads', helper)
        self.assertIn('_is_generated_road_child(node)', added)
        self.assertIn('_reset_scene_binding()', added)
        self.assertIn('_start_watching()', added)
        self.assertIn('_schedule_bind()', added)

    def test_unrelated_addition_does_not_invalidate_live_binding(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")
        added = _function_block(text, "_on_node_added(")
        self.assertIn('if is_instance_valid(_scene):', added)
        self.assertIn('if not _is_generated_road_child(node):', added)
        self.assertIn('return', added)
        self.assertNotIn('node.name.begins_with("Road_")', added)


if __name__ == "__main__":
    unittest.main()
