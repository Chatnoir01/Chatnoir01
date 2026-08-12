from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
PLAYER = ROOT / "game" / "scripts" / "player_controller.gd"
WEB_WORKFLOW = ROOT.parent / ".github" / "workflows" / "grand-bruxelles-web.yml"


class BourseDirectSpawnRegression(unittest.TestCase):
    def test_player_accepts_only_explicit_bourse_user_arg(self) -> None:
        text = PLAYER.read_text(encoding="utf-8")
        self.assertIn('OS.get_cmdline_user_args()', text)
        self.assertIn('spawn=bourse', text)
        self.assertIn('BOURSE_DIRECT_SPAWN_POSITION', text)
        self.assertIn('Vector3(83.44, 1.05, -663.42)', text)

    def test_web_query_is_wired_as_user_argument(self) -> None:
        text = WEB_WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("get('spawn')", text)
        self.assertIn("DIRECT_SPAWN === 'bourse'", text)
        self.assertIn("GODOT_CONFIG.args = ['--', 'spawn=bourse'];", text)


if __name__ == "__main__":
    unittest.main()
