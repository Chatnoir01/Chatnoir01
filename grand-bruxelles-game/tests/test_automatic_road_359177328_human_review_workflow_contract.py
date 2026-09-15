#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
WORKFLOW = PROJECT.parent / ".github" / "workflows" / "grand-bruxelles-automatic-road-359177328-human-review-veto.yml"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"AUTOMATIC_ROAD_359177328_HUMAN_REVIEW_WORKFLOW_CONTRACT_FAIL: {message}")


def main() -> int:
    text = WORKFLOW.read_text(encoding="utf-8")

    require("workflow_dispatch:" in text, "manual dispatch coverage missing")
    require("fetch-depth: 0" in text, "full history required for merge-base provenance")
    require("git fetch origin main --no-tags" in text, "live main must be fetched")
    require('live_main="$(git rev-parse origin/main)"' in text, "live-main identity capture missing")
    require('head_sha="$(git rev-parse HEAD)"' in text, "checked-out HEAD identity capture missing")
    require('merge_base="$(git merge-base HEAD origin/main)"' in text, "merge-base capture missing")
    require('test "$head_sha" = "${{ github.event.pull_request.head.sha }}"' in text, "PR head identity check missing")
    require('test "$head_sha" = "${{ github.sha }}"' in text, "manual-dispatch head identity check missing")
    require('test "$merge_base" = "$live_main"' in text, "exact-current-main merge-base check missing")

    provenance = text.index("- name: Require exact live-main merge base")
    veto = text.index("- name: Enforce immutable human REJECT")
    require(provenance < veto, "provenance gate must execute before immutable human veto")

    print("AUTOMATIC_ROAD_359177328_HUMAN_REVIEW_WORKFLOW_CONTRACT_OK all_trigger_provenance=true order_locked=true")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
