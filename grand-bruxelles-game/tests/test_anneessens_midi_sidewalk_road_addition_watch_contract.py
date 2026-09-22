from pathlib import Path
import unittest

RUNTIME = Path(__file__).resolve().parents[1] / "game" / "scripts" / "anneessens_midi_sidewalk_runtime.gd"


def _function_block(text: str, name: str) -> str:
    marker = f"func {name}"
    start = text.index(marker)
    next_func = text.find("\nfunc ", start + len(marker))
    return text[start:] if next_func == -1 else text[start:next_func]


class AnneessensMidiRoadAdditionWatchContract(unittest.TestCase):
    def test_new_generated_road_is_watched_before_binding_is_invalidated(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")
        node_added = _function_block(text, "_on_node_added(")

        self.assertIn("_is_generated_road_child(node)", node_added)
        self.assertIn("_watch_alignment_road_mutations(node as CSGBox3D)", node_added)
        self.assertLess(
            node_added.index("_watch_alignment_road_mutations(node as CSGBox3D)"),
            node_added.index("_reset_scene_binding()"),
            "A newly added GeneratedRoad must enter the mutation watch set before any rebuild decision.",
        )

    def test_addition_path_does_not_create_a_second_polling_mechanism(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")
        node_added = _function_block(text, "_on_node_added(")
        self.assertNotIn("Timer.new()", node_added)
        self.assertNotIn("_process", node_added)


if __name__ == "__main__":
    unittest.main()
