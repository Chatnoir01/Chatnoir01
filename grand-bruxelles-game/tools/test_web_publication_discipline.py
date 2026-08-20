#!/usr/bin/env python3
from __future__ import annotations

import json
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
WEB = REPO_ROOT / ".github/workflows/grand-bruxelles-web.yml"
PAGES = REPO_ROOT / ".github/workflows/grand-bruxelles-pages.yml"
HYGIENE = REPO_ROOT / ".github/workflows/grand-bruxelles-branch-hygiene.yml"
C01_LOCK = (
    REPO_ROOT
    / "grand-bruxelles-game/data/qa/region_lod2_campaigns/region_lod2_C01_30000.external_cell_delivery.lock.json"
)
C01_LOCK_TOOL = "grand-bruxelles-game/tools/qa/lock_region_lod2_c01_external_cell_delivery.py"
C01_PUBLIC_ROOT = "region-lod2/C01"
ARTIFACT = "grand-bruxelles-playable-web"


class WebPublicationDisciplineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.web = WEB.read_text(encoding="utf-8")
        cls.pages = PAGES.read_text(encoding="utf-8")
        cls.hygiene = HYGIENE.read_text(encoding="utf-8")
        cls.c01_lock = json.loads(C01_LOCK.read_text(encoding="utf-8"))

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

    def test_web_build_observes_all_pages_delivery_inputs(self) -> None:
        for path in (
            '.github/workflows/grand-bruxelles-pages.yml',
            'grand-bruxelles-game/data/qa/region_lod2_campaigns/region_lod2_C01_30000.external_cell_delivery.lock.json',
            'grand-bruxelles-game/tools/qa/lock_region_lod2_c01_external_cell_delivery.py',
        ):
            self.assertIn(f'- "{path}"', self.web, path)

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

    def test_pages_stages_locked_c01_cells_outside_web_pck(self) -> None:
        lock_rel = str(C01_LOCK.relative_to(REPO_ROOT))
        self.assertIn(f'"{lock_rel}"', self.pages)
        self.assertIn(f'"{C01_LOCK_TOOL}"', self.pages)
        self.assertIn("name: Stage locked C01 external LoD2 cells outside Web PCK", self.pages)
        self.assertIn(f"python3 {C01_LOCK_TOOL}", self.pages)
        self.assertIn('--artifact-dir "$RUNNER_TEMP/c01-final-world"', self.pages)
        self.assertIn(f'target="grand-bruxelles-game/web-preview/{C01_PUBLIC_ROOT}"', self.pages)
        self.assertIn('cp -a "$RUNNER_TEMP/c01-final-world/cells" "$target/cells"', self.pages)
        self.assertIn("C01_PAGES_EXTERNAL_DELIVERY_STAGED", self.pages)
        self.assertIn(f'$base/{C01_PUBLIC_ROOT}/external_cell_delivery_manifest.json', self.pages)
        self.assertIn("C01_PUBLIC_EXTERNAL_DELIVERY_OK", self.pages)
        self.assertNotIn("runtime_mount_authorized=true", self.pages)
        self.assertNotIn("collision_authorized=true", self.pages)

    def test_c01_pages_delivery_keeps_runtime_rails_closed(self) -> None:
        self.assertEqual(self.c01_lock["campaign_id"], "region-lod2-C01-30000")
        self.assertEqual(self.c01_lock["expected"]["spatial_cells"], 132)
        self.assertFalse(self.c01_lock["delivery"]["public_base_url_locked"])
        hard = self.c01_lock["hard_rules"]
        for key in (
            "runtime_authorized",
            "runtime_mount_authorized",
            "collision_authorized",
            "terrain_runtime_authorized",
            "jouable_promotion_authorized",
            "web_pck_embedded",
        ):
            self.assertFalse(hard[key], key)

    def test_branch_hygiene_observes_live_main_not_only_pr_base(self) -> None:
        self.assertIn("git fetch --no-tags origin main:refs/remotes/origin/main", self.hygiene)
        self.assertIn('LIVE_MAIN_SHA="$(git rev-parse refs/remotes/origin/main)"', self.hygiene)
        self.assertIn('git rev-list --count "$LIVE_MAIN_SHA..$HEAD_SHA"', self.hygiene)
        self.assertIn('git rev-list --count "$HEAD_SHA..$LIVE_MAIN_SHA"', self.hygiene)
        self.assertIn("behind live main", self.hygiene)


if __name__ == "__main__":
    unittest.main(verbosity=2)
