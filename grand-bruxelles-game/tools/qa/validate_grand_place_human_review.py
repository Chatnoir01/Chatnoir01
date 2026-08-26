#!/usr/bin/env python3
"""Fail-closed validator for persisted Grand-Place full-frame human review provenance.

This validates that a persisted review is internally coherent and cryptographically bound
to a real exact-head artifact naming convention. It deliberately never converts a human
KEEP into production/JOUABLE authorization; visual promotion remains a separate owner gate.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

SHA256 = re.compile(r"^[0-9a-f]{64}$")
ARTIFACT_DIGEST = re.compile(r"^sha256:[0-9a-f]{64}$")
ARTIFACT_NAME = re.compile(r"^grand-place-facade-engine-evidence-([0-9a-f]{40})$")
ALLOWED_FRAME_VERDICTS = {"keep", "reject"}
ALLOWED_OVERALL_VERDICTS = {"keep", "reject"}


class HumanReviewValidationError(ValueError):
    pass


def _fail(message: str) -> None:
    raise HumanReviewValidationError(message)


def _positive_int(name: str, value: Any) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        _fail(f"{name} must be a positive integer")
    return value


def _load_gate(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        _fail(f"cannot read gate JSON {path}: {exc}")
    if not isinstance(data, dict):
        _fail("gate JSON root must be an object")
    return data


def validate_human_review(gate: dict[str, Any]) -> dict[str, Any]:
    if not isinstance(gate, dict):
        _fail("gate must be an object")
    review = gate.get("latest_human_review")
    if not isinstance(review, dict):
        _fail("latest_human_review must be an object")

    run_id = _positive_int("run_id", review.get("run_id"))
    artifact_id = _positive_int("artifact_id", review.get("artifact_id"))

    artifact_name = review.get("artifact_name")
    if not isinstance(artifact_name, str):
        _fail("artifact name must be a string")
    match = ARTIFACT_NAME.fullmatch(artifact_name)
    if match is None:
        _fail("artifact name must bind exactly to a 40-character lowercase review head SHA")
    reviewed_head_sha = match.group(1)

    if review.get("artifact_exact_head") is not True:
        _fail("artifact_exact_head must be true for the persisted review artifact")

    artifact_digest = review.get("artifact_digest")
    if not isinstance(artifact_digest, str) or ARTIFACT_DIGEST.fullmatch(artifact_digest) is None:
        _fail("artifact digest must be sha256:<64 lowercase hex>")

    manifest_sha = review.get("runtime_manifest_sha256")
    if not isinstance(manifest_sha, str) or SHA256.fullmatch(manifest_sha) is None:
        _fail("manifest sha256 must be 64 lowercase hex characters")

    if review.get("full_frame_inspected") is not True:
        _fail("full-frame inspection must be explicitly true before persisting human review")

    frames = review.get("frames")
    if not isinstance(frames, dict) or len(frames) != 4:
        _fail("persisted human review must contain exactly four reviewed frames")

    frame_verdicts: list[str] = []
    frame_hashes: set[str] = set()
    for frame_name, frame in frames.items():
        if not isinstance(frame_name, str) or not frame_name.endswith(".png"):
            _fail("review frame names must be PNG artifact paths")
        if not isinstance(frame, dict):
            _fail(f"review frame entry must be an object: {frame_name!r}")
        frame_sha = frame.get("sha256")
        if not isinstance(frame_sha, str) or SHA256.fullmatch(frame_sha) is None:
            _fail(f"frame sha256 must be 64 lowercase hex characters: {frame_name!r}")
        if frame_sha in frame_hashes:
            _fail("each reviewed view must bind to a distinct frame sha256")
        frame_hashes.add(frame_sha)
        verdict = frame.get("verdict")
        if verdict not in ALLOWED_FRAME_VERDICTS:
            _fail(f"frame verdict must be one of {sorted(ALLOWED_FRAME_VERDICTS)}: {frame_name!r}")
        frame_verdicts.append(verdict)

    overall = review.get("overall_verdict")
    if overall not in ALLOWED_OVERALL_VERDICTS:
        _fail(f"overall verdict must be one of {sorted(ALLOWED_OVERALL_VERDICTS)}")
    derived = "reject" if "reject" in frame_verdicts else "keep"
    if overall != derived:
        _fail(f"overall verdict is inconsistent with reviewed frames: expected {derived!r}")

    return {
        "run_id": run_id,
        "artifact_id": artifact_id,
        "artifact_name": artifact_name,
        "artifact_digest": artifact_digest,
        "runtime_manifest_sha256": manifest_sha,
        "reviewed_head_sha": reviewed_head_sha,
        "artifact_exact_head": True,
        "full_frame_inspected": True,
        "frame_count": len(frames),
        "overall_verdict": overall,
        "visual_approval_claimed": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("gate", type=Path)
    args = parser.parse_args()
    result = validate_human_review(_load_gate(args.gate))
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
