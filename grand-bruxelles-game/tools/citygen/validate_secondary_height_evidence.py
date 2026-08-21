#!/usr/bin/env python3
"""Validate CityGen height candidates against independent semantic 3D evidence.

This evidence-only frontier accepts the autonomous measured height-candidate payload
(or the legacy manual-frontier review for compatibility). It can mark individual
DSM-DTM candidates as secondary-validated, but it can never approve runtime heights
or terrain.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from typing import Any

FORMAT = "grand-bruxelles-citygen-secondary-height-validation-v1"
REVIEW_FORMAT = "grand-bruxelles-citygen-manual-frontier-review-v1"
HEIGHT_CANDIDATES_FORMAT = "grand-bruxelles-cell-building-height-candidates-v1"
SECONDARY_SCHEMA = "grand-bruxelles-ixelles-semantic-dsm-comparison-v1"
CRS = "EPSG:31370"
HEIGHT_MATCH_EPSILON_M = 0.02


def _read(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def _digest(value: Any) -> str:
    payload = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def _finite_float(value: Any) -> float | None:
    try:
        out = float(value)
    except (TypeError, ValueError):
        return None
    return out if math.isfinite(out) else None


def _normalize_candidate_source(source: dict[str, Any]) -> dict[str, Any]:
    source_format = source.get("format")
    if source_format == REVIEW_FORMAT:
        if source.get("crs") != CRS:
            raise ValueError("unsupported CityGen manual frontier review")
        if source.get("runtime_promotion_allowed") is not False:
            raise ValueError("manual frontier review must forbid runtime promotion")
        height_review = source.get("height_review") or {}
        candidates = height_review.get("candidates") or []
        if not isinstance(candidates, list):
            raise ValueError("manual frontier height candidates are invalid")
        if int(height_review.get("candidate_count", len(candidates))) != len(candidates):
            raise ValueError("manual frontier candidate count drifted")
        return {
            "kind": "legacy_manual_frontier_review",
            "cell_id": source.get("cell_id"),
            "candidates": candidates,
            "candidate_digest": height_review.get("source_candidate_digest"),
            "review_digest": source.get("review_digest"),
            "blockers": list(source.get("blockers") or []),
        }

    if source_format == HEIGHT_CANDIDATES_FORMAT:
        if source.get("crs") != CRS:
            raise ValueError("unsupported autonomous CityGen height candidates")
        if source.get("runtime_promotion_allowed") is not False:
            raise ValueError("autonomous height candidates must forbid runtime promotion")
        buildings = source.get("buildings") or []
        if not isinstance(buildings, list):
            raise ValueError("autonomous height candidate rows are invalid")
        candidates: list[dict[str, Any]] = []
        for row in buildings:
            if not isinstance(row, dict):
                raise ValueError("autonomous height candidate row is invalid")
            if row.get("runtime_approved") is not False:
                raise ValueError("autonomous height candidate unexpectedly carries runtime approval")
            if _finite_float(row.get("candidate_height_m")) is not None:
                candidates.append(row)
        if int(source.get("candidate_count", len(candidates))) != len(candidates):
            raise ValueError("autonomous height candidate count drifted")
        return {
            "kind": "autonomous_measured_height_candidates",
            "cell_id": source.get("cell_id"),
            "candidates": candidates,
            "candidate_digest": source.get("candidate_digest"),
            "review_digest": None,
            "blockers": list(source.get("blockers") or []),
        }

    raise ValueError(f"unsupported CityGen height candidate source: {source_format!r}")


def validate(candidate_source_path: Path, secondary_path: Path) -> dict[str, Any]:
    source = _read(candidate_source_path)
    secondary = _read(secondary_path)
    normalized = _normalize_candidate_source(source)

    if secondary.get("schema") != SECONDARY_SCHEMA or secondary.get("source_crs") != CRS:
        raise ValueError("unsupported independent semantic height evidence")
    if secondary.get("runtime_approved") is not False or (secondary.get("policy") or {}).get("runtime_approval") is not False:
        raise ValueError("secondary height evidence must remain runtime-unapproved")

    cell_id = normalized["cell_id"]
    if not isinstance(cell_id, str) or secondary.get("cell") != cell_id:
        raise ValueError("secondary height evidence cell identity mismatch")

    candidates = normalized["candidates"]
    records = secondary.get("records") or []
    if not isinstance(records, list):
        raise ValueError("secondary height records are invalid")
    secondary_by_id: dict[str, dict[str, Any]] = {}
    for record in records:
        if not isinstance(record, dict):
            continue
        building_id = str(record.get("building_id") or "")
        if not building_id:
            continue
        if record.get("runtime_approved") is not False:
            raise ValueError(f"secondary building evidence must remain runtime-unapproved: {building_id}")
        if building_id in secondary_by_id:
            raise ValueError(f"duplicate secondary building evidence: {building_id}")
        secondary_by_id[building_id] = record

    validated_rows: list[dict[str, Any]] = []
    validated_count = 0
    blocked_count = 0
    for candidate in candidates:
        if not isinstance(candidate, dict):
            raise ValueError("height candidate row is invalid")
        building_id = str(candidate.get("building_id") or "")
        candidate_height = _finite_float(candidate.get("candidate_height_m"))
        if not building_id or candidate_height is None:
            raise ValueError("height candidate is missing identity or finite height")
        if candidate.get("runtime_approved") not in (None, False):
            raise ValueError(f"height candidate unexpectedly carries runtime approval: {building_id}")

        record = secondary_by_id.get(building_id)
        status = "blocked_missing_secondary_evidence"
        reason = "no matching independent semantic height record"
        semantic_height = None
        abs_delta = None
        match_score = None
        match_margin = None
        if record is not None:
            semantic_height = _finite_float(record.get("semantic_height_m"))
            abs_delta = _finite_float(record.get("abs_delta_m"))
            match_score = _finite_float(record.get("semantic_match_score"))
            match_margin = _finite_float(record.get("semantic_match_margin"))
            secondary_candidate = _finite_float(record.get("dsm_policy_candidate_m"))
            if secondary_candidate is None or abs(secondary_candidate - candidate_height) > HEIGHT_MATCH_EPSILON_M:
                status = "blocked_candidate_mismatch"
                reason = "secondary evidence DSM policy candidate does not match the measured CityGen candidate"
            elif record.get("agreement") == "conflict":
                status = "blocked_conflict"
                reason = "independent semantic height conflicts with DSM-DTM candidate"
            elif record.get("strong_validation_candidate") is True and record.get("agreement") == "strong":
                status = "validated"
                reason = "strong independent semantic agreement with source-matched high-confidence DSM-DTM candidate"
            else:
                status = "blocked_insufficient_secondary_confidence"
                reason = "secondary evidence did not satisfy the strong independent validation contract"

        if status == "validated":
            validated_count += 1
        else:
            blocked_count += 1
        validated_rows.append({
            "building_id": building_id,
            "candidate_height_m": candidate_height,
            "confidence": str(candidate.get("confidence") or ""),
            "secondary_status": status,
            "secondary_reason": reason,
            "semantic_height_m": semantic_height,
            "abs_delta_m": abs_delta,
            "semantic_match_score": match_score,
            "semantic_match_margin": match_margin,
            "runtime_approved": False,
        })

    blockers = [
        str(value)
        for value in normalized["blockers"]
        if str(value) != "secondary_independent_height_validation_missing"
    ]
    complete = bool(candidates) and blocked_count == 0
    if candidates and not complete:
        blockers.append("secondary_independent_height_validation_incomplete")
    if not candidates:
        blockers.append("secondary_height_validation_has_no_measured_candidates")

    result = {
        "format": FORMAT,
        "cell_id": cell_id,
        "crs": CRS,
        "height_candidate_source_kind": normalized["kind"],
        "source_review_digest": normalized["review_digest"],
        "source_candidate_digest": normalized["candidate_digest"],
        "secondary_schema": secondary.get("schema"),
        "secondary_evidence_digest": _digest(secondary),
        "candidate_count": len(candidates),
        "validated_candidate_count": validated_count,
        "blocked_candidate_count": blocked_count,
        "secondary_validation_complete": complete,
        "candidates": sorted(validated_rows, key=lambda row: row["building_id"]),
        "blockers": sorted(set(blockers)),
        "runtime_promotion_allowed": False,
        "runtime_approved_count": 0,
        "next_action": (
            "run_remaining_terrain_runtime_gates_then_promotion_readiness"
            if complete
            else "resolve_blocked_secondary_height_candidates_without_guessing"
        ),
    }
    result["validation_digest"] = _digest(result)
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--height-candidates", type=Path)
    source.add_argument("--review", type=Path, help="legacy compatibility path")
    parser.add_argument("--secondary", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    source_path = args.height_candidates or args.review
    result = validate(source_path, args.secondary)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        "CITYGEN_SECONDARY_HEIGHT_VALIDATION_OK",
        result["cell_id"],
        f"source={result['height_candidate_source_kind']}",
        f"validated={result['validated_candidate_count']}",
        f"blocked={result['blocked_candidate_count']}",
        "runtime_promotion=false",
    )


if __name__ == "__main__":
    main()
