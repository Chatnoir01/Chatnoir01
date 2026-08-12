#!/usr/bin/env python3
"""Validate Grand Bruxelles photo-match QA manifests.

This gate intentionally allows references to remain incomplete while work is in
progress. A reference may only be marked ``realism_complete`` when its matching
in-game capture, quantitative scores and mismatch resolution prove that claim.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Any

SCORE_FIELDS = (
    "silhouette",
    "building_placement",
    "height_roofline",
    "street_width",
    "curb_sidewalk_proportions",
    "landmark_alignment",
    "vegetation",
    "street_furniture",
    "materials",
    "lighting",
    "major_visual_clutter",
)


def fail(message: str) -> None:
    print(f"PHOTO_MATCH_QA_FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        fail(f"manifest not found: {path}")
    except json.JSONDecodeError as exc:
        fail(f"invalid JSON in {path}: {exc}")
    if not isinstance(value, dict):
        fail("manifest root must be an object")
    return value


def require_text(obj: dict[str, Any], key: str, context: str) -> str:
    value = obj.get(key)
    if not isinstance(value, str) or not value.strip():
        fail(f"{context}.{key} must be a non-empty string")
    return value.strip()


def validate_score(value: Any, context: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        fail(f"{context} must be numeric")
    score = float(value)
    if not math.isfinite(score) or not 0.0 <= score <= 5.0:
        fail(f"{context} must be within 0..5")
    return score


def resolve_project_root(manifest_path: Path) -> Path:
    resolved = manifest_path.resolve()
    for parent in [resolved.parent, *resolved.parents]:
        if (parent / "project.godot").is_file():
            return parent
    fail("could not locate project.godot above manifest")
    raise AssertionError("unreachable")


def validate_manifest(manifest_path: Path) -> tuple[int, int]:
    manifest = load_json(manifest_path)
    if manifest.get("schema_version") != 1:
        fail("schema_version must be 1")

    scale = manifest.get("score_scale")
    if not isinstance(scale, dict):
        fail("score_scale must be an object")
    if scale.get("min") != 0 or scale.get("max") != 5:
        fail("score_scale min/max must remain 0/5")
    passing_average = validate_score(scale.get("passing_average"), "score_scale.passing_average")
    critical_fields = scale.get("critical_fields")
    if not isinstance(critical_fields, list) or not critical_fields:
        fail("score_scale.critical_fields must be a non-empty array")
    for field in critical_fields:
        if field not in SCORE_FIELDS:
            fail(f"unknown critical score field: {field}")

    references = manifest.get("references")
    if not isinstance(references, list) or not references:
        fail("references must be a non-empty array")

    project_root = resolve_project_root(manifest_path)
    ids: set[str] = set()
    complete_count = 0

    for index, raw_reference in enumerate(references):
        context = f"references[{index}]"
        if not isinstance(raw_reference, dict):
            fail(f"{context} must be an object")
        reference_id = require_text(raw_reference, "id", context)
        if reference_id in ids:
            fail(f"duplicate reference id: {reference_id}")
        ids.add(reference_id)
        require_text(raw_reference, "hero_location", context)
        require_text(raw_reference, "zone", context)

        source = raw_reference.get("reference")
        if not isinstance(source, dict):
            fail(f"{context}.reference must be an object")
        source_page = require_text(source, "source_page", f"{context}.reference")
        if not source_page.startswith("https://"):
            fail(f"{context}.reference.source_page must be HTTPS")
        require_text(source, "captured_at", f"{context}.reference")
        require_text(source, "author", f"{context}.reference")
        require_text(source, "license", f"{context}.reference")
        require_text(source, "distribution_policy", f"{context}.reference")
        require_text(source, "camera_notes", f"{context}.reference")

        viewpoint = raw_reference.get("viewpoint")
        if not isinstance(viewpoint, dict):
            fail(f"{context}.viewpoint must be an object")
        require_text(viewpoint, "description", f"{context}.viewpoint")

        scores = raw_reference.get("scores")
        if not isinstance(scores, dict):
            fail(f"{context}.scores must be an object")
        missing_score_keys = [field for field in SCORE_FIELDS if field not in scores]
        if missing_score_keys:
            fail(f"{context}.scores missing keys: {', '.join(missing_score_keys)}")

        mismatches = raw_reference.get("mismatches")
        if not isinstance(mismatches, list):
            fail(f"{context}.mismatches must be an array")
        for mismatch_index, mismatch in enumerate(mismatches):
            mismatch_context = f"{context}.mismatches[{mismatch_index}]"
            if not isinstance(mismatch, dict):
                fail(f"{mismatch_context} must be an object")
            severity = require_text(mismatch, "severity", mismatch_context)
            if severity not in {"info", "minor", "major", "blocker"}:
                fail(f"{mismatch_context}.severity invalid: {severity}")
            require_text(mismatch, "action", mismatch_context)
            resolved = mismatch.get("resolved", False)
            if not isinstance(resolved, bool):
                fail(f"{mismatch_context}.resolved must be boolean when present")

        realism_complete = raw_reference.get("realism_complete")
        if not isinstance(realism_complete, bool):
            fail(f"{context}.realism_complete must be boolean")

        if not realism_complete:
            if not mismatches:
                fail(f"{context} is incomplete but has no actionable mismatch")
            continue

        camera_transform = viewpoint.get("game_camera_transform")
        screenshot = viewpoint.get("game_screenshot")
        if camera_transform is None:
            fail(f"{context} marked complete without game_camera_transform")
        if not isinstance(camera_transform, dict):
            fail(f"{context}.viewpoint.game_camera_transform must be an object")
        for transform_key in ("position", "rotation_degrees", "fov_degrees"):
            if transform_key not in camera_transform:
                fail(f"{context}.viewpoint.game_camera_transform missing {transform_key}")

        if not isinstance(screenshot, str) or not screenshot.strip():
            fail(f"{context} marked complete without game_screenshot")
        screenshot_path = (project_root / screenshot).resolve()
        try:
            screenshot_path.relative_to(project_root.resolve())
        except ValueError:
            fail(f"{context}.viewpoint.game_screenshot escapes project root")
        if not screenshot_path.is_file():
            fail(f"{context}.viewpoint.game_screenshot does not exist: {screenshot}")

        numeric_scores = {
            field: validate_score(scores[field], f"{context}.scores.{field}")
            for field in SCORE_FIELDS
        }
        average = sum(numeric_scores.values()) / len(numeric_scores)
        if average < passing_average:
            fail(
                f"{context} average {average:.2f} is below passing threshold "
                f"{passing_average:.2f}"
            )
        for critical_field in critical_fields:
            if numeric_scores[critical_field] < passing_average:
                fail(
                    f"{context} critical score {critical_field}="
                    f"{numeric_scores[critical_field]:.2f} is below {passing_average:.2f}"
                )

        unresolved_blockers = [
            mismatch
            for mismatch in mismatches
            if mismatch.get("severity") == "blocker" and not mismatch.get("resolved", False)
        ]
        if unresolved_blockers:
            fail(f"{context} marked complete with unresolved blocker mismatch")
        complete_count += 1

    return len(references), complete_count


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "manifest",
        nargs="?",
        default="grand-bruxelles-game/data/qa/photo_match/manifest.json",
    )
    args = parser.parse_args()
    total, complete = validate_manifest(Path(args.manifest))
    print(
        "PHOTO_MATCH_QA_OK: "
        f"{total} registered reference(s), {complete} realism-complete, "
        f"{total - complete} intentionally incomplete"
    )


if __name__ == "__main__":
    main()
