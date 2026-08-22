#!/usr/bin/env python3
"""Canonical fail-closed blocker classification for Grand Bruxelles CityGen."""
from __future__ import annotations

from typing import Any, Iterable

RULES = (
    ("HEIGHT_CONFLICT", ("height conflict", "hauteur conflic", "secondary conflict", "conflicting height"), False, "request_manual_height_review"),
    ("STALE_SOURCE", ("stale source", "source revision is stale", "source too old", "freshness", "stale revision"), True, "refresh_authoritative_source"),
    ("MISSING_DTM", ("missing dtm", "dtm missing", "no dtm", "dtm unavailable"), True, "resolve_official_dtm_source"),
    ("MISSING_OSM", ("missing osm", "osm missing", "no osm", "osm cache"), True, "refresh_or_materialize_osm_cache"),
    ("MISSING_VISUAL_PROOF", ("visual proof", "photo_match", "photo match", "player witness", "screenshot proof"), True, "run_visual_witness_gate"),
    ("MISSING_RUNTIME_GATE", ("runtime gate", "collision gate", "streaming gate", "performance gate", "missing gate", "gate missing"), True, "run_missing_runtime_gate"),
    ("RUNTIME_WIRING", ("runtime_consumes_city_machine_outputs", "legacy runtime", "runtime wiring", "runtime not wired", "legacy output"), True, "wire_runtime_to_city_machine_outputs"),
    ("OWNERSHIP_CONFLICT", ("ownership conflict", "owned by", "file overlap", "concurrent owner"), False, "rebuild_on_fresh_main_or_wait_for_owner"),
    ("PARTIAL_COVERAGE", ("partial coverage", "coverage_complete=false", "coverage incomplete", "incomplete coverage"), True, "continue_partial_zone_evidence"),
    ("MISSING_SOURCE", ("missing source", "source missing", "no source", "missing authoritative"), True, "materialize_authoritative_source"),
)


def _text(blocker: Any) -> str:
    if isinstance(blocker, str):
        return blocker.strip()
    if isinstance(blocker, dict):
        for key in ("detail", "reason", "message", "status", "code"):
            value = blocker.get(key)
            if value:
                return str(value).strip()
        return str(blocker)
    return str(blocker).strip()


def classify_blocker(blocker: Any) -> dict[str, Any]:
    detail = _text(blocker)
    lower = detail.lower()
    code = "UNKNOWN_HOLD"
    auto = False
    action = "manual_triage_required"
    for candidate, needles, candidate_auto, candidate_action in RULES:
        if any(needle in lower for needle in needles):
            code, auto, action = candidate, candidate_auto, candidate_action
            break
    return {
        "code": code,
        "auto_resolvable": auto,
        "recommended_action": action,
        "detail": detail,
        "runtime_authorized": False,
        "jouable_authorized": False,
    }


def resolve_blockers(blockers: Iterable[Any]) -> list[dict[str, Any]]:
    rows = [classify_blocker(b) for b in blockers if _text(b)]
    rows.sort(key=lambda row: (row["code"], row["detail"]))
    return rows
