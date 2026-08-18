#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path


CANONICAL_URL = "https://chatnoir01.github.io/Chatnoir01/"
RAWGITHACK_URL = (
    "https://raw.githack.com/Chatnoir01/Chatnoir01/main/"
    "grand-bruxelles-game/web-preview/index.html"
)
DEAD_URL = "https://grand-bruxelles-game-hchxi.vercel.app"
ARTIFACT_NAME = "grand-bruxelles-playable-web"


def main() -> None:
    game_root = Path(__file__).resolve().parents[1]
    repository_root = game_root.parent
    readme = (game_root / "README.md").read_text(encoding="utf-8")
    play = (game_root / "PLAY.md").read_text(encoding="utf-8")
    workflow = (
        repository_root / ".github/workflows/grand-bruxelles-pages.yml"
    ).read_text(encoding="utf-8")
    web_build_workflow = (
        repository_root / ".github/workflows/grand-bruxelles-web.yml"
    ).read_text(encoding="utf-8")

    assert CANONICAL_URL in play, "PLAY.md must expose the single canonical GitHub Pages URL"
    assert "Lien unique" in play
    assert "PLAYABLE_PAGES_OK" in play
    assert "RawGitHack n’est pas une solution finale" in play
    assert "Settings → Pages → Build and deployment → Source → GitHub Actions" in play

    assert CANONICAL_URL in readme, "README must document the canonical GitHub Pages URL"
    assert DEAD_URL not in readme, "README must not advertise the removed Vercel deployment"
    assert "URL canonique prévue" in readme, "README must not claim Pages is live before activation"
    assert "Settings → Pages → Build and deployment → Source = GitHub Actions" in readme
    assert "ne doit plus être communiqué comme URL joueur principale" in readme

    assert "name: Grand Bruxelles Playable Link" in workflow
    assert '"grand-bruxelles-game/PLAY.md"' in workflow
    assert "pull_request:" in workflow
    assert "workflow_run:" in workflow
    assert 'workflows: ["Grand Bruxelles Playable Web Build"]' in workflow
    assert "name: Checkout proposed source" in workflow
    assert "if: github.event_name == 'workflow_run'" in workflow
    assert "python3 grand-bruxelles-game/tools/test_playable_link_contract.py" in workflow
    assert 'ref: ${{ github.event.workflow_run.head_sha }}' in workflow
    assert 'run-id: ${{ github.event.workflow_run.id }}' in workflow
    assert workflow.count("uses: actions/download-artifact@v4") >= 2
    assert workflow.count(f"name: {ARTIFACT_NAME}") >= 2
    assert "push:\n    branches: [\"main\"]" not in workflow, (
        "Pages production deployment must be driven by the successful Web workflow artifact, "
        "not a second push-main path that can deploy an old committed snapshot"
    )

    assert "pages_state:" in workflow
    assert "https://api.github.com/repos/${GITHUB_REPOSITORY}/pages" in workflow
    assert 'if [ "$code" = "200" ]' in workflow
    assert 'elif [ "$code" = "404" ]' in workflow
    assert "PAGES_SITE_READY" in workflow
    assert "PAGES_ENABLEMENT_REQUIRED" in workflow

    assert "deploy_pages:" in workflow
    assert "needs.pages_state.outputs.enabled == 'true'" in workflow
    assert "pages: write" in workflow
    assert "id-token: write" in workflow
    assert "actions: read" in workflow
    assert "uses: actions/configure-pages@v6" in workflow
    assert "enablement: true" not in workflow, "workflow must not retry forbidden first-time Pages creation"
    assert "uses: actions/upload-pages-artifact@v4" in workflow
    assert "path: grand-bruxelles-game/web-preview" in workflow
    assert "uses: actions/deploy-pages@v4" in workflow

    assert "verify_public:" in workflow
    assert "PLAYABLE_PUBLIC_BASE: ${{ needs.deploy_pages.outputs.page_url }}" in workflow
    assert "PLAYABLE_PAGES_OK" in workflow
    assert "access_status:" in workflow
    assert "PLAYABLE_ACCESS_READY" in workflow
    assert "raw.githack.com" not in workflow, "public verification must not depend on RawGitHack"
    assert RAWGITHACK_URL not in workflow

    assert "permissions:\n  contents: read" in web_build_workflow
    assert "contents: write" not in web_build_workflow
    assert "uses: actions/upload-artifact@v4" in web_build_workflow
    assert f"name: {ARTIFACT_NAME}" in web_build_workflow
    assert "if-no-files-found: error" in web_build_workflow
    for forbidden in ("git push", "git commit", "git rebase", "git add -f"):
        assert forbidden not in web_build_workflow, (
            f"Web publication must not mutate main; forbidden command remains: {forbidden}"
        )

    print(
        "PLAYABLE_LINK_CONTRACT_TEST_OK "
        "single_play_entry=true pages_first=true artifact_handoff=true "
        "main_mutation=false pages_initial_admin_gate=explicit rawgithack_primary=false"
    )


if __name__ == "__main__":
    main()
