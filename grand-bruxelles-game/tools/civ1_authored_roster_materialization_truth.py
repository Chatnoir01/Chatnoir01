#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path

import civ1_authored_roster_promotion_truth as promotion

SCHEMA = "grand-bruxelles-civ1-authored-roster-materialization-truth-v1"


def res_path_to_file(project_root: Path, res_path: str) -> Path:
    if not res_path.startswith("res://"):
        raise ValueError(f"not a Godot res path: {res_path}")
    return project_root / res_path.removeprefix("res://")


def analyze(scene: str, visual: str, project_root: Path) -> dict[str, object]:
    base = promotion.analyze(scene, visual)
    correlated = list(base.get("correlated_authored_asset_paths", []))
    materialized: list[str] = []
    missing_or_empty: list[str] = []
    for res_path in correlated:
        backing = res_path_to_file(project_root, res_path)
        if backing.is_file() and backing.stat().st_size > 0:
            materialized.append(res_path)
        else:
            missing_or_empty.append(res_path)

    all_materialized = bool(correlated) and not missing_or_empty
    multiple_materialized = len(materialized) >= 2
    static_ready = bool(base.get("authored_civilian_police_roster_visual_ready"))
    ready = static_ready and all_materialized and multiple_materialized

    blockers = list(base.get("blocking_reasons", []))
    if correlated and missing_or_empty:
        blockers.append("correlated_authored_npc_assets_missing_or_empty")
    if static_ready and not multiple_materialized:
        blockers.append("multiple_materialized_authored_npc_identities_not_proven")

    return {
        "schema": SCHEMA,
        "promotion_truth_schema": base.get("schema"),
        "correlated_authored_asset_paths": correlated,
        "materialized_correlated_authored_asset_paths": sorted(materialized),
        "missing_or_empty_correlated_authored_asset_paths": sorted(missing_or_empty),
        "correlated_asset_backing_required": True,
        "all_correlated_authored_asset_backings_materialized": all_materialized,
        "multiple_materialized_authored_npc_identities_proven": multiple_materialized,
        "static_authored_roster_ready": static_ready,
        "authored_civilian_police_roster_materialization_ready": ready,
        "promotion_blocked": not ready,
        "blocking_reasons": blockers,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "contact_verified": False,
        "foot_slide_verified": False,
    }


def main() -> int:
    if len(sys.argv) != 5:
        print("usage: civ1_authored_roster_materialization_truth.py MAIN_TSCN HUMANOID_VISUAL PROJECT_ROOT OUT", file=sys.stderr)
        return 2
    scene_path = Path(sys.argv[1])
    visual_path = Path(sys.argv[2])
    project_root = Path(sys.argv[3])
    result = analyze(scene_path.read_text(encoding="utf-8"), visual_path.read_text(encoding="utf-8"), project_root)
    out = Path(sys.argv[4])
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
