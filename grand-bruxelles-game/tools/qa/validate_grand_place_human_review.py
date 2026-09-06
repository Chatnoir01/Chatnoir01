#!/usr/bin/env python3
"""Fail-closed validator for persisted Grand-Place full-frame human review provenance.

This validates the receipt schema that is actually stored in the frozen facade gate. It
checks provenance, cryptographic bindings and verdict consistency only. It deliberately
never promotes a human KEEP to production/JOUABLE authorization; promotion remains a
separate owner decision after the other frozen gates.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

SHA40 = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
ARTIFACT_DIGEST = re.compile(r"^sha256:[0-9a-f]{64}$")
ALLOWED_VIEW_VERDICTS = {"keep", "reject"}
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

    evidence_contract = gate.get("evidence_contract")
    if not isinstance(evidence_contract, dict):
        _fail("evidence_contract must be an object")
    required_view_ids = evidence_contract.get("required_view_ids")
    if (
        not isinstance(required_view_ids, list)
        or len(required_view_ids) != 4
        or len(set(required_view_ids)) != 4
        or not all(isinstance(view_id, str) and view_id for view_id in required_view_ids)
    ):
        _fail("evidence contract must define exactly four distinct required view ids")
    required_png_names = {f"{view_id}.png" for view_id in required_view_ids}

    required_resolution = evidence_contract.get("required_resolution")
    if required_resolution != gate.get("resolution") or required_resolution != [1280, 720]:
        _fail("frozen evidence resolution must remain exactly 1280x720")

    review = gate.get("latest_human_review")
    if not isinstance(review, dict):
        _fail("latest_human_review must be an object")

    reviewed_head_sha = review.get("head_sha")
    if not isinstance(reviewed_head_sha, str) or SHA40.fullmatch(reviewed_head_sha) is None:
        _fail("review head sha must be 40 lowercase hexadecimal characters")

    workflow_run_id = _positive_int("workflow_run_id", review.get("workflow_run_id"))
    artifact_id = _positive_int("artifact_id", review.get("artifact_id"))

    artifact_digest = review.get("artifact_digest")
    if not isinstance(artifact_digest, str) or ARTIFACT_DIGEST.fullmatch(artifact_digest) is None:
        _fail("artifact digest must be sha256:<64 lowercase hex>")

    manifest_sha = review.get("manifest_sha256")
    if not isinstance(manifest_sha, str) or SHA256.fullmatch(manifest_sha) is None:
        _fail("manifest sha256 must be 64 lowercase hex characters")

    resolution = review.get("resolution")
    if resolution != required_resolution:
        _fail(f"human-review resolution drifted: expected {required_resolution!r}, got {resolution!r}")

    if review.get("full_frame_inspected") is not True:
        _fail("full-frame inspection must be explicitly true before persisting human review")

    if review.get("source_geometry_changed") is not False:
        _fail("source geometry must remain unchanged in a persisted presentation-only review")
    if review.get("source_collision_changed") is not False:
        _fail("source collision must remain unchanged in a persisted presentation-only review")

    png_sha256 = review.get("png_sha256")
    if not isinstance(png_sha256, dict) or set(png_sha256) != required_png_names:
        _fail("persisted human review must bind exactly the four required PNG views")

    seen_hashes: set[str] = set()
    for png_name in sorted(required_png_names):
        frame_sha = png_sha256.get(png_name)
        if not isinstance(frame_sha, str) or SHA256.fullmatch(frame_sha) is None:
            _fail(f"frame sha256 must be 64 lowercase hex characters: {png_name!r}")
        if frame_sha in seen_hashes:
            _fail("each reviewed view must bind to a distinct frame sha256")
        seen_hashes.add(frame_sha)

    view_verdicts = review.get("view_verdicts")
    if not isinstance(view_verdicts, dict) or not view_verdicts:
        _fail("view_verdicts must contain at least one explicit reviewed view")
    unknown_views = set(view_verdicts) - set(required_view_ids)
    if unknown_views:
        _fail(f"view verdict contains unknown required-view ids: {sorted(unknown_views)!r}")
    for view_id, verdict in view_verdicts.items():
        if verdict not in ALLOWED_VIEW_VERDICTS:
            _fail(f"view verdict must be one of {sorted(ALLOWED_VIEW_VERDICTS)}: {view_id!r}")

    overall = review.get("overall_verdict")
    if overall not in ALLOWED_OVERALL_VERDICTS:
        _fail(f"overall verdict must be one of {sorted(ALLOWED_OVERALL_VERDICTS)}")
    rejected_views = sorted(view_id for view_id, verdict in view_verdicts.items() if verdict == "reject")
    if overall == "reject" and not rejected_views:
        _fail("reject overall verdict requires at least one explicitly rejected view")
    if overall == "keep":
        if set(view_verdicts) != set(required_view_ids):
            _fail("keep overall verdict requires explicit keep for all required views")
        if any(verdict != "keep" for verdict in view_verdicts.values()):
            _fail("keep overall verdict is inconsistent with a rejected view")

    return {
        "workflow_run_id": workflow_run_id,
        "artifact_id": artifact_id,
        "artifact_digest": artifact_digest,
        "manifest_sha256": manifest_sha,
        "reviewed_head_sha": reviewed_head_sha,
        "full_frame_inspected": True,
        "frame_count": len(png_sha256),
        "overall_verdict": overall,
        "rejected_views": rejected_views,
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
