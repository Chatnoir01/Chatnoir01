#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path


LIVE_URL = (
    "https://raw.githack.com/Chatnoir01/Chatnoir01/main/"
    "grand-bruxelles-game/web-preview/index.html"
)
DEAD_URL = "https://grand-bruxelles-game-hchxi.vercel.app"


def main() -> None:
    game_root = Path(__file__).resolve().parents[1]
    repository_root = game_root.parent
    readme = (game_root / "README.md").read_text(encoding="utf-8")
    workflow = (
        repository_root / ".github/workflows/grand-bruxelles-pages.yml"
    ).read_text(encoding="utf-8")

    assert LIVE_URL in readme, "README must expose the verified playable URL"
    assert DEAD_URL not in readme, "README must not advertise the removed Vercel deployment"

    assert "name: Grand Bruxelles Playable Link" in workflow
    assert "pull_request:" in workflow
    assert "name: Checkout proposed source" in workflow
    assert "if: github.event_name == 'workflow_run'" in workflow
    assert "PLAYABLE_PUBLIC_BASE:" in workflow
    assert LIVE_URL.rsplit("/", 1)[0] in workflow
    assert "python3 grand-bruxelles-game/tools/test_playable_link_contract.py" in workflow
    assert "name: Verify public playable link" in workflow

    assert "deploy_pages:" in workflow
    assert "github.event_name == 'workflow_dispatch' && inputs.deploy_pages" in workflow
    assert "uses: actions/deploy-pages@v4" in workflow

    print("PLAYABLE_LINK_CONTRACT_TEST_OK")


if __name__ == "__main__":
    main()
