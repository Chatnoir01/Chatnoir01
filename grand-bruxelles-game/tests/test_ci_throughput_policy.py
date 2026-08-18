import unittest
from pathlib import Path

ROOT = Path(__file__).parents[2]
GAME_CI = ROOT / ".github" / "workflows" / "grand-bruxelles-game.yml"
NPM_CI = ROOT / ".github" / "workflows" / "test.yml"


class CiThroughputPolicyTests(unittest.TestCase):
    def test_game_ci_targets_product_paths_not_docs_tree(self):
        workflow = GAME_CI.read_text(encoding="utf-8")
        self.assertNotIn('- "grand-bruxelles-game/**"', workflow)
        self.assertIn('- "grand-bruxelles-game/game/**"', workflow)
        self.assertIn('- "grand-bruxelles-game/data/**"', workflow)
        self.assertIn('- "grand-bruxelles-game/tools/**"', workflow)
        self.assertIn('- "grand-bruxelles-game/tests/**"', workflow)
        self.assertNotIn('- "grand-bruxelles-game/docs/**"', workflow)

    def test_npm_ci_skips_docs_only_changes(self):
        workflow = NPM_CI.read_text(encoding="utf-8")
        self.assertGreaterEqual(workflow.count("paths-ignore:"), 2)
        self.assertGreaterEqual(workflow.count('- "grand-bruxelles-game/docs/**"'), 2)
        self.assertGreaterEqual(workflow.count('- "**/*.md"'), 2)


if __name__ == "__main__":
    unittest.main()
