#!/usr/bin/env python3
"""Classify blocked CityGen secondary-height candidates into evidence queues.

This module is intentionally read-only and fail-closed. It does not change the
secondary-height validator, comparison thresholds, candidate heights, geometry,
terrain, collisions, or runtime approval. Its only job is to state what kind of
additional evidence is required before a blocked candidate could be reconsidered.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from typing import Any

SCHEMA = "grand-bruxelles-citygen-blocked-secondary-height-triage-v1"
VALIDATION_FORMAT = "grand-bruxelles-citygen-secondary-height-validation-v1"
SECONDARY_SCHEMA = "grand-bruxelles-ixelles-semantic-dsm-comparison-v1"
CRS = "EPSG:31370"

ROUTES = (
    "secondary_coverage_gap",
    "candidate_provenance_mismatch",
    "independent_height_adjudication_required",
    "primary_confidence_corroboration_required",
    "cross_source_height_adjudication_required",
    "dual_uncertainty_requires_new_evidence",
    "unclassified_blocked_secondary_evidence",
)

ADJUDICATION_ROUTES = {
    "independent_height_adjudication_required",
    "primary_confidence_corroboration_required",
    "cross_source_height_adjudication_required",
    "dual_uncertainty_requires_new_evidence",
}


def _read(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def _digest(value: Any) -> str:
    payload = json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=False
    ).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def _finite(value: Any) -> float | None:
    try:
        result = float(value)
    except (TypeError, ValueError):
        return None
    return result if math.isfinite(result) else None


def _route_for(candidate: dict[str, Any], record: dict[str, Any] | None) -> tuple[str, str]:
    status = str(candidate.get("secondary_status") or "")
    confidence = str(candidate.get("confidence") or "")
    agreement = str((record or {}).get("agreement") or "")

    if status == "blocked_missing_secondary_evidence":
        return (
            "secondary_coverage_gap",
            "obtain authoritative independent secondary coverage or a newer source snapshot; do not invent a spatial match",
        )
    if status == "blocked_candidate_mismatch":
        return (
            "candidate_provenance_mismatch",
            "rebuild and verify the measured candidate provenance/digest against the secondary evidence before reconsideration",
        )
    if status == "blocked_conflict":
        return (
            "independent_height_adjudication_required",
            "obtain a new independent authoritative height source or keep the candidate quarantined",
        )
    if status == "blocked_insufficient_secondary_confidence":
        if agreement == "strong" and confidence == "medium":
            return (
                "primary_confidence_corroboration_required",
                "corroborate the medium-confidence DSM-DTM primary measurement with independent authoritative evidence; do not lower the high-confidence requirement",
            )
        if agreement == "moderate" and confidence == "high":
            return (
                "cross_source_height_adjudication_required",
                "obtain another authoritative height observation to adjudicate the moderate cross-source delta; do not widen the strong-agreement threshold",
            )
        if agreement == "moderate" and confidence == "medium":
            return (
                "dual_uncertainty_requires_new_evidence",
                "obtain new authoritative evidence because both the primary confidence and cross-source agreement are insufficient",
            )

    return (
        "unclassified_blocked_secondary_evidence",
        "retain fail-closed quarantine and collect source-specific evidence before any policy or runtime decision",
    )


def triage(validation: dict[str, Any], secondary: dict[str, Any]) -> dict[str, Any]:
    if validation.get("format") != VALIDATION_FORMAT:
        raise ValueError("unsupported secondary-height validation format")
    if validation.get("crs") != CRS:
        raise ValueError("secondary-height validation must remain EPSG:31370")
    if validation.get("runtime_promotion_allowed") is not False:
        raise ValueError("secondary-height validation unexpectedly allows runtime promotion")
    if validation.get("runtime_approved_count") != 0:
        raise ValueError("secondary-height validation unexpectedly carries runtime approval")

    if secondary.get("schema") != SECONDARY_SCHEMA:
        raise ValueError("unsupported semantic DSM comparison schema")
    if secondary.get("source_crs") != CRS:
        raise ValueError("semantic DSM comparison must remain EPSG:31370")
    if secondary.get("runtime_approved") is not False:
        raise ValueError("semantic DSM comparison unexpectedly carries runtime approval")
    if (secondary.get("policy") or {}).get("runtime_approval") is not False:
        raise ValueError("semantic DSM comparison policy must forbid runtime approval")

    cell_id = validation.get("cell_id")
    if not isinstance(cell_id, str) or not cell_id or secondary.get("cell") != cell_id:
        raise ValueError("secondary-height triage cell identity mismatch")

    candidates = validation.get("candidates")
    records = secondary.get("records")
    if not isinstance(candidates, list) or not isinstance(records, list):
        raise ValueError("secondary-height triage inputs must contain candidate/record lists")

    candidate_by_id: dict[str, dict[str, Any]] = {}
    for candidate in candidates:
        if not isinstance(candidate, dict):
            raise ValueError("invalid validation candidate row")
        building_id = str(candidate.get("building_id") or "")
        if not building_id or building_id in candidate_by_id:
            raise ValueError(f"invalid or duplicate validation candidate: {building_id!r}")
        if candidate.get("runtime_approved") is not False:
            raise ValueError(f"validation candidate unexpectedly runtime-approved: {building_id}")
        candidate_by_id[building_id] = candidate

    secondary_by_id: dict[str, dict[str, Any]] = {}
    for record in records:
        if not isinstance(record, dict):
            raise ValueError("invalid secondary evidence record")
        building_id = str(record.get("building_id") or "")
        if not building_id:
            continue
        if building_id in secondary_by_id:
            raise ValueError(f"duplicate secondary evidence record: {building_id}")
        if record.get("runtime_approved") is not False:
            raise ValueError(f"secondary evidence unexpectedly runtime-approved: {building_id}")
        secondary_by_id[building_id] = record

    declared_candidate_count = validation.get("candidate_count")
    declared_validated_count = validation.get("validated_candidate_count")
    declared_blocked_count = validation.get("blocked_candidate_count")
    if not all(isinstance(value, int) and not isinstance(value, bool) and value >= 0 for value in (
        declared_candidate_count, declared_validated_count, declared_blocked_count
    )):
        raise ValueError("validation candidate counts are invalid")
    if declared_candidate_count != len(candidates):
        raise ValueError("validation candidate count drifted")

    measured_validated = sum(candidate.get("secondary_status") == "validated" for candidate in candidates)
    measured_blocked = len(candidates) - measured_validated
    if declared_validated_count != measured_validated or declared_blocked_count != measured_blocked:
        raise ValueError("validation blocked/validated counts drifted")

    blocked_candidates: list[dict[str, Any]] = []
    counts = {route: 0 for route in ROUTES}

    for building_id, candidate in sorted(candidate_by_id.items()):
        status = str(candidate.get("secondary_status") or "")
        if status == "validated":
            continue

        record = secondary_by_id.get(building_id)
        route, evidence_request = _route_for(candidate, record)
        counts[route] += 1
        blocked_candidates.append({
            "building_id": building_id,
            "secondary_status": status,
            "secondary_reason": str(candidate.get("secondary_reason") or ""),
            "triage_route": route,
            "evidence_request": evidence_request,
            "candidate_height_m": _finite(candidate.get("candidate_height_m")),
            "confidence": str(candidate.get("confidence") or ""),
            "semantic_height_m": _finite(candidate.get("semantic_height_m")),
            "abs_delta_m": _finite(candidate.get("abs_delta_m")),
            "semantic_match_score": _finite(candidate.get("semantic_match_score")),
            "semantic_match_margin": _finite(candidate.get("semantic_match_margin")),
            "agreement": str((record or {}).get("agreement") or ""),
            "strong_validation_candidate": bool((record or {}).get("strong_validation_candidate") is True),
            "automatic_resolution_allowed": False,
            "runtime_approved": False,
        })

    counts.update({
        "candidate_total": len(candidates),
        "validated_ignored": measured_validated,
        "blocked_total": measured_blocked,
        "adjudication_frontier": sum(
            1 for row in blocked_candidates if row["triage_route"] in ADJUDICATION_ROUTES
        ),
    })
    if counts["blocked_total"] != len(blocked_candidates):
        raise ValueError("triage blocked candidate count drifted")
    if sum(counts[route] for route in ROUTES) != counts["blocked_total"]:
        raise ValueError("triage route counts do not cover every blocked candidate")

    result: dict[str, Any] = {
        "schema": SCHEMA,
        "cell_id": cell_id,
        "crs": CRS,
        "validation_format": VALIDATION_FORMAT,
        "secondary_schema": SECONDARY_SCHEMA,
        "source_validation_digest": validation.get("validation_digest") or _digest(validation),
        "source_secondary_digest": validation.get("secondary_evidence_digest") or _digest(secondary),
        "policy": {
            "read_only": True,
            "automatic_resolution": False,
            "thresholds_changed": False,
            "runtime_approval": False,
            "note": "triage routes describe missing evidence only; they never validate or promote a blocked height candidate",
        },
        "counts": counts,
        "blocked_candidates": blocked_candidates,
        "runtime_promotion_allowed": False,
        "runtime_approved_count": 0,
        "next_action": "collect_required_authoritative_evidence_without_guessing",
    }
    result["triage_digest"] = _digest(result)
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--validation", type=Path, required=True)
    parser.add_argument("--secondary", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    result = triage(_read(args.validation), _read(args.secondary))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(
        "BLOCKED_SECONDARY_HEIGHT_TRIAGE_OK",
        result["cell_id"],
        f"blocked={result['counts']['blocked_total']}",
        f"adjudication={result['counts']['adjudication_frontier']}",
        "runtime_promotion=false",
        "thresholds_changed=false",
    )


if __name__ == "__main__":
    main()
