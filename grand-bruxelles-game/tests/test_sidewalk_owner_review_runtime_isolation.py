#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
QUEUE_PATH = ROOT / "data/provenance/brussels_sidewalk_owner_review_queue.json"
PROJECT_PATH = ROOT / "project.godot"
PRODUCTION_ROOT = ROOT / "game"

FORBIDDEN_TOKENS = (
    "brussels_sidewalk_owner_review_queue.json",
    "grand-bruxelles-sidewalk-owner-review-queue-v1",
)
TEXT_SUFFIXES = {".gd", ".tscn", ".tres", ".cfg", ".json"}


def _assert_queue_is_fail_closed() -> tuple[int, int]:
    assert QUEUE_PATH.exists(), f"owner-review queue missing: {QUEUE_PATH}"
    payload = json.loads(QUEUE_PATH.read_text(encoding="utf-8"))
    assert payload.get("schema") == "grand-bruxelles-sidewalk-owner-review-queue-v1"

    policy = payload.get("policy", {})
    assert policy.get("exact_location_owner_review_required") is True
    assert policy.get("nearest_anchor_role") == "triage_only"
    assert policy.get("nearest_anchor_authorizes_ownership") is False
    for key in (
        "runtime_geometry_authorized",
        "runtime_replacement_authorized",
        "curb_height_authorized",
        "vertical_profile_authorized",
        "jouable_promotion_authorized",
    ):
        assert policy.get(key) is False, f"queue policy unexpectedly authorizes {key}"

    queue = payload.get("queue", [])
    assert len(queue) == 27, f"expected 27 review runs, got {len(queue)}"
    surface_count = 0
    for item in queue:
        assert item.get("exact_location_owner_review_required") is True
        assert item.get("nearest_anchor_role") == "triage_only"
        assert item.get("nearest_anchor_authorizes_ownership") is False
        assert item.get("runtime_replacement_authorized") is False
        surface_count += int(item.get("surface_count", 0))
    assert surface_count == 47, f"expected 47 queued surfaces, got {surface_count}"
    return len(queue), surface_count


def _scan_runtime_for_forbidden_consumers() -> list[str]:
    offenders: list[str] = []
    candidates: list[Path] = []
    if PROJECT_PATH.exists():
        candidates.append(PROJECT_PATH)
    if PRODUCTION_ROOT.exists():
        candidates.extend(
            path
            for path in PRODUCTION_ROOT.rglob("*")
            if path.is_file() and path.suffix.lower() in TEXT_SUFFIXES
        )

    for path in sorted(candidates):
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        matched = [token for token in FORBIDDEN_TOKENS if token in text]
        if matched:
            rel = path.relative_to(ROOT).as_posix()
            offenders.append(f"{rel}: {', '.join(matched)}")
    return offenders


def main() -> None:
    run_count, surface_count = _assert_queue_is_fail_closed()
    offenders = _scan_runtime_for_forbidden_consumers()
    assert not offenders, (
        "owner-review queue is triage/provenance-only and must not be consumed by canonical runtime before explicit exact-location authorization:\n"
        + "\n".join(offenders)
    )
    print(
        "SIDEWALK_OWNER_REVIEW_RUNTIME_ISOLATION_OK: "
        f"runs={run_count} surfaces={surface_count} runtime_consumers=0 "
        "nearest_anchor_role=triage_only ownership_authorized=false"
    )


if __name__ == "__main__":
    main()
