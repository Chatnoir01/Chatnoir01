from pathlib import Path
import unittest

RUNTIME = Path(__file__).resolve().parents[1] / "game" / "scripts" / "anneessens_midi_sidewalk_runtime.gd"


class AnneessensMidiSidewalkMutationImportSafety(unittest.TestCase):
    """Keep the mutation callback import-safe under Godot warning-as-error CI.

    Node3D exposes `transform_changed` as a signal. A local with the same identifier
    in the callback is ambiguous/shadowing-prone and must not be reintroduced.
    """

    def test_mutation_callback_does_not_shadow_transform_changed_signal(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")
        callback = text.split(
            "func _on_alignment_road_mutated(instance_id: Variant) -> void:", 1
        )[1].split("\nfunc ", 1)[0]
        self.assertNotIn("var transform_changed :=", callback)
        self.assertIn("road.global_transform", callback)
        self.assertIn("road.size", callback)


if __name__ == "__main__":
    unittest.main()
