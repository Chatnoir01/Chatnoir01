#!/usr/bin/env python3
"""Read-only stale-PR and ownership-overlap planner for Grand Bruxelles."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

SCHEMA = "grand-bruxelles-pr-drift-plan-v1"


def _files(row: dict[str, Any]) -> set[str]:
    return {str(x) for x in (row.get("changed_files") or []) if x}


def build_drift_plan(snapshot: dict[str, Any], *, max_commits: int = 20, max_age_hours: int = 72) -> dict[str, Any]:
    raw = sorted(snapshot.get("prs") or [], key=lambda r: int(r["number"]))
    file_sets = {int(r["number"]): _files(r) for r in raw}
    rows = []

    for pr in raw:
        number = int(pr["number"])
        overlaps = []
        for other in raw:
            other_number = int(other["number"])
            if other_number == number:
                continue
            shared = sorted(file_sets[number] & file_sets[other_number])
            if shared:
                overlaps.append({"with_pr": other_number, "files": shared})
        overlaps.sort(key=lambda x: x["with_pr"])

        behind = max(0, int(pr.get("behind_by") or 0))
        commits = max(0, int(pr.get("commits") or 0))
        age_hours = max(0.0, float(pr.get("age_hours") or 0.0))
        long_lived = commits >= max_commits or age_hours >= max_age_hours
        files_complete = bool(pr.get("files_complete", True))

        if not files_complete:
            state = "OWNERSHIP_UNCERTAIN"
            auto_rebuild = False
            action = "complete_file_inventory_before_rebuild"
        elif overlaps:
            state = "OWNERSHIP_CONFLICT"
            auto_rebuild = False
            action = "coordinate_owner_before_rebuild"
        elif behind > 0:
            state = "REBUILD_REQUIRED"
            auto_rebuild = True
            action = "rebuild_patch_from_live_main"
        else:
            state = "CURRENT"
            auto_rebuild = False
            action = "keep_short_and_merge_or_close"

        rows.append({
            "number": number,
            "title": pr.get("title"),
            "url": pr.get("url"),
            "head_ref": pr.get("head_ref"),
            "head_sha": pr.get("head_sha"),
            "behind_by": behind,
            "commits": commits,
            "age_hours": age_hours,
            "changed_file_count": len(file_sets[number]),
            "files_complete": files_complete,
            "overlaps": overlaps,
            "state": state,
            "rebuild_required": state == "REBUILD_REQUIRED",
            "auto_rebuild_candidate": auto_rebuild,
            "long_lived_risk": long_lived,
            "recommended_action": action,
            "automatic_merge_allowed": False,
            "automatic_force_push_allowed": False,
        })

    return {
        "schema": SCHEMA,
        "main_sha": snapshot.get("main_sha"),
        "automatic_merge_allowed": False,
        "automatic_force_push_allowed": False,
        "thresholds": {"max_commits": max_commits, "max_age_hours": max_age_hours},
        "prs": rows,
        "summary": {
            "open_pr_count": len(rows),
            "current_count": sum(r["state"] == "CURRENT" for r in rows),
            "rebuild_required_count": sum(r["state"] == "REBUILD_REQUIRED" for r in rows),
            "ownership_conflict_count": sum(r["state"] == "OWNERSHIP_CONFLICT" for r in rows),
            "ownership_uncertain_count": sum(r["state"] == "OWNERSHIP_UNCERTAIN" for r in rows),
            "long_lived_risk_count": sum(r["long_lived_risk"] for r in rows),
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--snapshot", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--max-commits", type=int, default=20)
    parser.add_argument("--max-age-hours", type=int, default=72)
    args = parser.parse_args()
    snapshot = json.loads(args.snapshot.read_text(encoding="utf-8"))
    plan = build_drift_plan(snapshot, max_commits=args.max_commits, max_age_hours=args.max_age_hours)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(plan, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(plan["summary"], sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
