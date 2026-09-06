#!/usr/bin/env python3
"""Finalize Anneessens witness evidence without allowing machine visual promotion."""
from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

FRAME = "automatic_road_1382734012_player.png"
MANIFEST = "evidence-manifest.json"
LOG = "runtime.log"
SIDECAR = "evidence-sha256.txt"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fail(message: str) -> None:
    raise AssertionError(message)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: finalize_anneessens_human_review_policy.py <stage-dir>", file=sys.stderr)
        return 2

    stage = Path(sys.argv[1])
    manifest_path = stage / MANIFEST
    log_path = stage / LOG
    frame_path = stage / FRAME
    sidecar_path = stage / SIDECAR
    for path in (manifest_path, log_path, frame_path):
        if not path.is_file() or path.stat().st_size == 0:
            fail(f"missing or empty evidence file: {path.name}")

    payload = json.loads(manifest_path.read_text(encoding="utf-8"))
    log = log_path.read_text(encoding="utf-8", errors="replace")
    traces = re.findall(r"ANNEESSENS_VISUAL_BLOCKER_TRACE: sample=\([^\n]+", log)
    building_hits = sum("hit=true" in row and "collider_name=Building_" in row for row in traces)
    source_sha_matches = payload.get("source_sha_matches") is True
    candidate_meets_frozen_ray_rule = len(traces) == 3 and 1 <= building_hits <= 2 and source_sha_matches

    if payload.get("human_review_required") is not True:
        fail("human review must remain required")
    if payload.get("destination_advertisable") is not False:
        fail("machine witness may not advertise destination readiness")
    if payload.get("jouable_authorized") is not False:
        fail("machine witness may not authorize JOUABLE")

    payload["candidate_meets_frozen_ray_rule"] = candidate_meets_frozen_ray_rule
    payload["visual_acceptance"] = False
    manifest_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    sidecar_path.write_text(
        f"{sha256(frame_path)}  {FRAME}\n"
        f"{sha256(manifest_path)}  {MANIFEST}\n"
        f"{sha256(log_path)}  {LOG}\n",
        encoding="utf-8",
    )

    finalized = json.loads(manifest_path.read_text(encoding="utf-8"))
    if finalized.get("visual_acceptance") is not False:
        fail("final evidence must keep visual_acceptance=false")
    if finalized.get("candidate_meets_frozen_ray_rule") is not candidate_meets_frozen_ray_rule:
        fail("candidate ray-rule receipt drifted during finalization")

    print(
        "ANNEESSENS_HUMAN_REVIEW_POLICY_GREEN "
        f"candidate_meets_frozen_ray_rule={str(candidate_meets_frozen_ray_rule).lower()} "
        "visual_acceptance=false human_review_required=true"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, json.JSONDecodeError) as exc:
        print(f"ANNEESSENS_HUMAN_REVIEW_POLICY_FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
