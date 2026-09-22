import pathlib
import unittest


RUNTIME = pathlib.Path(__file__).resolve().parents[1] / "game" / "scripts" / "anneessens_midi_sidewalk_runtime.gd"


class AnneessensMidiSidewalkBusyParentReleaseTest(unittest.TestCase):
    def test_owned_root_release_is_deferred_out_of_tree_callbacks(self) -> None:
        source = RUNTIME.read_text(encoding="utf-8")
        release = source.split("func _release_owned_root() -> void:", 1)[1].split("\nfunc ", 1)[0]
        self.assertNotIn("parent.remove_child(_root)", release)
        self.assertIn('call_deferred("_detach_and_free_owned_root", owned_root)', release)
        self.assertIn("func _detach_and_free_owned_root(owned_root: Node3D) -> void:", source)
        helper = source.split("func _detach_and_free_owned_root(owned_root: Node3D) -> void:", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn("parent.remove_child(owned_root)", helper)
        self.assertIn("owned_root.queue_free()", helper)


if __name__ == "__main__":
    unittest.main()
