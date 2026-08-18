#!/usr/bin/env python3
from __future__ import annotations

import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
WEB = REPO_ROOT / ".github/workflows/grand-bruxelles-web.yml"
PAGES = REPO_ROOT / ".github/workflows/grand-bruxelles-pages.yml"
HYGIENE = REPO_ROOT / ".github/workflows/grand-bruxelles-branch-hygiene.yml"
ARTIFACT = "grand-bruxelles-playable-web"


class WebPublicationDisciplineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.web = WEB.read_text(encoding="utf-8")
        cls.pages = PAGES.read_text(encoding="utf-8")
        cls.hygiene = HYGIENE.read_text(encoding="utf-8")

    def test_web_build_is_read_only_to_repository(self) -> None:
        self.assertIn("permissions:\n  contents: read", self.web)
        self.assertNotIn("contents: write", self.web)
        self.assertNotIn("git push", self.web)
        self.assertNotIn("git commit", self.web)
        self.assertNotIn("git rebase", self.web)
        self.assertNotIn("git add -f", self.web)

    def test_web_build_uploads_named_immutable_artifact(self) -> None:
        self.assertIn("uses: actions/upload-artifact@v4", self.web)
        self.assertIn(f"name: {ARTIFACT}", self.web)
        self.assertIn("path: grand-bruxelles-game/web-preview", self.web)
        self.assertIn("if-no-files-found: error", self.web)

    def test_pages_is_driven_by_successful_web_workflow_run(self) -> None:
        self.assertIn('workflows: ["Grand Bruxelles Playable Web Build"]', self.pages)
        self.assertIn("github.event.workflow_run.conclusion == 'success'", self.pages)
        self.assertIn("github.event.workflow_run.head_branch == 'main'", self.pages)
        self.assertNotIn("push:\n    branches: [\"main\"]", self.pages)

    def test_pages_downloads_exact_triggering_artifact_for_verify_and_deploy(self) -> None:
        self.assertGreaterEqual(self.pages.count("uses: actions/download-artifact@v4"), 2)
        self.assertGreaterEqual(self.pages.count(f"name: {ARTIFACT}"), 2)
        self.assertGreaterEqual(self.pages.count("run-id: ${{ github.event.workflow_run.id }}"), 2)
        self.assertGreaterEqual(self.pages.count("ref: ${{ github.event.workflow_run.head_sha }}"), 2)
        self.assertGreaterEqual(self.pages.count("actions: read"), 2)

    def test_pages_still_verifies_and_deploys_public_assets(self) -> None:
        self.assertIn("python3 grand-bruxelles-game/tools/test_playable_link_contract.py", self.pages)
        self.assertIn("uses: actions/upload-pages-artifact@v4", self.pages)
        self.assertIn("uses: actions/deploy-pages@v4", self.pages)
        self.assertIn("PLAYABLE_PAGES_OK", self.pages)

    def test_branch_hygiene_observes_live_main_not_only_pr_base(self) -> None:
        self.assertIn("git fetch --no-tags origin main:refs/remotes/origin/main", self.hygiene)
        self.assertIn('LIVE_MAIN_SHA="$(git rev-parse refs/remotes/origin/main)"', self.hygiene)
        self.assertIn('git rev-list --count "$LIVE_MAIN_SHA..$HEAD_SHA"', self.hygiene)
        self.assertIn('git rev-list --count "$HEAD_SHA..$LIVE_MAIN_SHA"', self.hygiene)
        self.assertIn("behind live main", self.hygiene)


if __name__ == "__main__":
    unittest.main(verbosity=2)
