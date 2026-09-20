from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "game" / "scripts" / "anneessens_midi_sidewalk_runtime.gd"


class AnneessensMidiSidewalkCollisionFailClosedTest(unittest.TestCase):
    def test_proxy_collision_contract_and_rendered_nodes_stay_disabled(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")

        # The authored sidewalk proxy has no source-backed vertical profile.  Its
        # metadata and actual CSG collision state must therefore fail closed together.
        self.assertIn('node.set_meta("collision_source_backed", false)', text)
        self.assertIn('node.set_meta("collision_authorized", false)', text)
        self.assertIn(
            'node.set_meta("collision_policy", "disabled_until_source_backed_vertical_profile")',
            text,
        )
        self.assertIn("pavement.use_collision = false", text)
        self.assertNotIn("pavement.use_collision = true", text)

    def test_visibility_toggle_cannot_become_a_collision_toggle(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")
        marker = "func set_sidewalks_enabled(enabled: bool) -> void:"
        self.assertIn(marker, text)
        toggle = text[text.index(marker) :]

        # This public presentation control is allowed to change visibility only.
        # It must keep every owned proxy non-colliding regardless of enabled state.
        self.assertIn("_root.visible = enabled", toggle)
        self.assertIn("pavement.use_collision = false", toggle)
        self.assertNotIn("pavement.use_collision = enabled", toggle)
        self.assertNotIn("pavement.use_collision = true", toggle)

    def test_collision_counter_has_no_increment_path(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")
        self.assertIn("var _collision_count := 0", text)
        self.assertIn("func diagnostic_collision_count() -> int:", text)
        self.assertNotIn("_collision_count +=", text)
        self.assertNotIn("_collision_count = _collision_count +", text)


if __name__ == "__main__":
    unittest.main()
