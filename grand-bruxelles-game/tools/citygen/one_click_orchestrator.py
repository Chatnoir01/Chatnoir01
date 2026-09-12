#!/usr/bin/env python3
"""Build a deterministic, read-only orchestration plan over City Machine zones.

This controller deliberately does not generate geometry, mutate main, authorize runtime,
or promote LABO to JOUABLE. Existing specialist workflows remain the executors.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from universal_zone_profile import analyse_zone

SCHEMA = "grand-bruxelles-one-click-plan-v1"


def build_plan(registry: dict[str, Any], catalog: dict[str, Any], facts: dict[str, Any] | None = None) -> dict[str, Any]:
    facts = facts or {}
    profiles = registry.get("zone_profiles") or {}
    catalog_rows = {str(row.get("id")): row for row in (catalog.get("zones") or []) if row.get("id")}
    zone_ids = sorted(set(profiles) | set(catalog_rows) | set(facts))

    zones = []
    queue = []
    for zone_id in zone_ids:
        result = analyse_zone(zone_id, profiles.get(zone_id), facts.get(zone_id) or {})
        result["catalog_quality"] = (catalog_rows.get(zone_id) or {}).get("quality")
        zones.append(result)
        for blocker in result["blockers"]:
            queue.append({
                "zone_id": zone_id,
                "code": blocker["code"],
                "auto_resolvable": blocker["auto_resolvable"],
                "recommended_action": blocker["recommended_action"],
                "detail": blocker["detail"],
            })

    queue.sort(key=lambda row: (not row["auto_resolvable"], row["zone_id"], row["code"], row["detail"]))
    lifecycle_counts = {
        state: 0
        for state in (
            "BLOCKED",
            "PARTIAL_DATA_READY",
            "DATA_READY",
            "RUNTIME_READY",
            "LABO_READY",
            "PROMOTION_REVIEW_REQUIRED",
        )
    }
    for zone in zones:
        lifecycle_counts[zone["lifecycle"]] += 1

    return {
        "schema": SCHEMA,
        "automatic_jouable_promotion": False,
        "automatic_main_mutation": False,
        "fail_closed": True,
        "zones": zones,
        "hold_queue": queue,
        "summary": {
            "zone_count": len(zones),
            "profiled_zone_count": sum(1 for z in zones if z["profile_present"]),
            "auto_resolvable_hold_count": sum(1 for q in queue if q["auto_resolvable"]),
            "manual_hold_count": sum(1 for q in queue if not q["auto_resolvable"]),
            "lifecycle_counts": lifecycle_counts,
        },
    }


def _load(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--registry", type=Path, required=True)
    parser.add_argument("--catalog", type=Path, required=True)
    parser.add_argument("--facts", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--fail-on-unknown", action="store_true")
    args = parser.parse_args()

    plan = build_plan(_load(args.registry), _load(args.catalog), _load(args.facts) if args.facts else {})
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(plan, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(plan["summary"], sort_keys=True))
    if args.fail_on_unknown and any(row["code"] == "UNKNOWN_HOLD" for row in plan["hold_queue"]):
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
