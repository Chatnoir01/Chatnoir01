from pathlib import Path
import unittest

RUNTIME = Path(__file__).resolve().parents[1] / "game" / "scripts" / "anneessens_midi_sidewalk_runtime.gd"


class AnneessensMidiSidewalkVisibilityCollisionClosed(unittest.TestCase):
    """Visibility toggles must never weaken the fail-closed collision contract."""

    def test_visibility_toggle_reasserts_collision_disabled_on_owned_sidewalks(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")
        block = text.split("func set_sidewalks_enabled(enabled: bool) -> void:", 1)[1]
        self.assertIn("_root.visible = enabled", block)
        self.assertIn("for child: Node in _root.get_children():", block)
        self.assertIn("if child is CSGBox3D:", block)
        self.assertIn("pavement.use_collision = false", block)


if __name__ == "__main__":
    unittest.main()
