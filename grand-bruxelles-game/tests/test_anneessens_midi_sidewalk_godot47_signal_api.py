from pathlib import Path
import unittest

RUNTIME = Path(__file__).resolve().parents[1] / "game" / "scripts" / "anneessens_midi_sidewalk_runtime.gd"


class AnneessensMidiSidewalkGodot47SignalApi(unittest.TestCase):
    """Keep mutation invalidation independent of unsupported/redundant signal APIs.

    CSGBox3D inherits CSGShape3D/Node3D. Godot 4.7.1 does not expose a
    CSGShape3D mesh_updated signal. The runtime's bounded 0.25 s snapshot poll
    owns both global_transform and size mutation detection, so it must not
    reintroduce a second transform_changed signal lifecycle either.
    """

    def test_runtime_does_not_reference_csg_mesh_updated_or_transform_signal_path(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")
        self.assertNotIn("road.mesh_updated", text)
        self.assertNotIn("road.transform_changed", text)
        self.assertNotIn("road.set_notify_transform(true)", text)
        self.assertIn("_alignment_road_transforms", text)
        self.assertIn("_alignment_road_sizes", text)
        self.assertIn("_poll_alignment_road_mutations", text)
        self.assertIn("road.global_transform", text)
        self.assertIn("road.size", text)


if __name__ == "__main__":
    unittest.main()
