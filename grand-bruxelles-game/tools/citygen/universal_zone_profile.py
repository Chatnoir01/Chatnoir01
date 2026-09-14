#!/usr/bin/env python3
"""Read-only universal zone maturity analysis for City Machine profiles."""
from __future__ import annotations

from typing import Any

from hold_resolver import resolve_blockers

LIFECYCLE = (
    "BLOCKED",
    "PARTIAL_DATA_READY",
    "DATA_READY",
    "RUNTIME_READY",
    "LABO_READY",
    "PROMOTION_REVIEW_REQUIRED",
)


def _has_data_shape(profile: dict[str, Any]) -> bool:
    slugs = set(profile.get("materialized_slugs") or [])
    return bool(profile.get("source_root")) and bool(slugs.intersection({"buildings", "street_surfaces", "street_axes"}))


def analyse_zone(zone_id: str, profile: dict[str, Any] | None, facts: dict[str, Any] | None = None) -> dict[str, Any]:
    profile = profile or {}
    facts = facts or {}
    blockers: list[Any] = list(facts.get("blockers") or [])

    has_data_shape = _has_data_shape(profile)
    source_ready = bool(facts.get("source_contract_ready", has_data_shape))
    coverage = facts.get("coverage_complete")
    runtime_wired = facts.get("runtime_consumes_city_machine_outputs")
    runtime_gates = bool(facts.get("runtime_gates_passed", False))
    labo_gates = bool(facts.get("labo_gates_passed", False))
    visual = bool(facts.get("visual_proof_passed", False))

    if not profile:
        blockers.append("missing source profile")
    elif not has_data_shape or not source_ready:
        blockers.append("missing authoritative source contract")

    if coverage is False:
        blockers.append("coverage_complete=false partial coverage")
    if runtime_wired is False:
        blockers.append("runtime_consumes_city_machine_outputs=false legacy runtime wiring")

    classified = resolve_blockers(blockers)
    hard_source_block = any(
        b["code"] in {"MISSING_SOURCE", "UNKNOWN_HOLD", "HEIGHT_CONFLICT", "OWNERSHIP_CONFLICT"}
        for b in classified
    )

    lifecycle = "BLOCKED"
    if source_ready and has_data_shape and not hard_source_block:
        lifecycle = "PARTIAL_DATA_READY" if coverage is False else "DATA_READY"
        runtime_blocked = any(
            b["code"] in {"RUNTIME_WIRING", "MISSING_RUNTIME_GATE", "UNKNOWN_HOLD", "HEIGHT_CONFLICT", "OWNERSHIP_CONFLICT"}
            for b in classified
        )
        if runtime_gates and runtime_wired is not False and not runtime_blocked:
            lifecycle = "RUNTIME_READY"
            if labo_gates:
                lifecycle = "LABO_READY"
                if visual:
                    lifecycle = "PROMOTION_REVIEW_REQUIRED"

    return {
        "zone_id": zone_id,
        "profile_present": bool(profile),
        "coverage_complete": coverage,
        "lifecycle": lifecycle,
        "blockers": classified,
        "auto_resolvable_hold_count": sum(1 for b in classified if b["auto_resolvable"]),
        "manual_hold_count": sum(1 for b in classified if not b["auto_resolvable"]),
        "runtime_authorized": False,
        "jouable_authorized": False,
        "automatic_production_mutation": False,
    }
