import importlib.util
import sys
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).parents[1] / "tools" / "validate_branch_hygiene.py"
WORKFLOW_PATH = Path(__file__).parents[2] / ".github" / "workflows" / "grand-bruxelles-branch-hygiene.yml"
SPEC = importlib.util.spec_from_file_location("validate_branch_hygiene", MODULE_PATH)
assert SPEC and SPEC.loader
MOD = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MOD
SPEC.loader.exec_module(MOD)


class BranchHygieneTests(unittest.TestCase):
    def test_rejects_specialist_on_specialist_base(self):
        result = MOD.check("systems-npc-police-civilians", "zone-laeken-jette", [])
        self.assertFalse(result.ok)
        self.assertTrue(any("must target main" in error for error in result.errors))

    def test_rejects_geographic_main_scene_edit(self):
        result = MOD.check("zone-laeken-jette", "main", ["grand-bruxelles-game/game/main.tscn"])
        self.assertFalse(result.ok)

    def test_rejects_contaminated_geographic_gameplay(self):
        result = MOD.check("zone-reste-bruxelles-clean", "main", ["grand-bruxelles-game/game/scripts/traffic_manager.gd"])
        self.assertFalse(result.ok)

    def test_quarantines_long_lived_specialist(self):
        result = MOD.check("zone-laeken-jette", "main", [], ahead=428, behind=0)
        self.assertFalse(result.ok)
        self.assertTrue(any("extract a coherent lot" in error for error in result.errors))

    def test_accepts_small_clean_integration_lot(self):
        result = MOD.check("integration/photo-match-qa-v2", "main", ["grand-bruxelles-game/tools/foo.py"], ahead=3, behind=0)
        self.assertTrue(result.ok)

    def test_rejects_stale_integration_lot(self):
        result = MOD.check("integration/npc-recovery", "main", ["grand-bruxelles-game/game/scripts/npc_agent.gd"], ahead=1, behind=1)
        self.assertFalse(result.ok)
        self.assertTrue(any("behind live main" in error for error in result.errors))

    def test_rejects_stale_regular_merge_candidate(self):
        result = MOD.check("qa/zone-contract", "main", ["grand-bruxelles-game/tools/foo.py"], ahead=1, behind=1)
        self.assertFalse(result.ok)
        self.assertTrue(any("behind live main" in error for error in result.errors))

    def test_rejects_stale_visual_merge_candidate(self):
        result = MOD.check("visual/midi-fonsny", "main", ["grand-bruxelles-game/game/scripts/foo.gd"], ahead=2, behind=1)
        self.assertFalse(result.ok)

    def test_accepts_non_overlapping_docs_only_live_main_drift(self):
        result = MOD.check(
            "visual/midi-fonsny",
            "main",
            ["grand-bruxelles-game/game/scripts/foo.gd"],
            ahead=2,
            behind=2,
            docs_only_drift=True,
        )
        self.assertTrue(result.ok)
        self.assertTrue(any("non-overlapping docs" in warning for warning in result.warnings))

    def test_docs_exception_is_not_implicit(self):
        result = MOD.check(
            "visual/midi-fonsny",
            "main",
            ["grand-bruxelles-game/game/scripts/foo.gd"],
            ahead=2,
            behind=2,
        )
        self.assertFalse(result.ok)

    def test_rejects_oversized_integration_lot(self):
        result = MOD.check("integration/shared-core-bundle", "main", ["grand-bruxelles-game/game/scripts/foo.gd"], ahead=21, behind=0)
        self.assertFalse(result.ok)
        self.assertTrue(any("smaller coherent promotion lots" in error for error in result.errors))

    def test_workflow_scopes_diff_to_pr_base_but_drift_to_live_main(self):
        workflow = WORKFLOW_PATH.read_text(encoding="utf-8")
        self.assertIn("BASE_SHA: ${{ github.event.pull_request.base.sha }}", workflow)
        self.assertIn("HEAD_SHA: ${{ github.event.pull_request.head.sha }}", workflow)
        self.assertIn('git diff --name-only "$BASE_SHA...$HEAD_SHA"', workflow)
        self.assertIn("git fetch --no-tags origin main:refs/remotes/origin/main", workflow)
        self.assertIn('LIVE_MAIN_SHA="$(git rev-parse refs/remotes/origin/main)"', workflow)
        self.assertIn('git rev-list --count "$LIVE_MAIN_SHA..$HEAD_SHA"', workflow)
        self.assertIn('git rev-list --count "$HEAD_SHA..$LIVE_MAIN_SHA"', workflow)
        self.assertIn('MERGE_BASE="$(git merge-base "$HEAD_SHA" "$LIVE_MAIN_SHA")"', workflow)
        self.assertIn('^grand-bruxelles-game/docs/', workflow)
        self.assertIn("DOCS_ONLY_DRIFT", workflow)
        self.assertIn("OVERLAP", workflow)
        self.assertIn("--docs-only-drift", workflow)
        self.assertIn("live main SHA", workflow)


if __name__ == "__main__":
    unittest.main()
