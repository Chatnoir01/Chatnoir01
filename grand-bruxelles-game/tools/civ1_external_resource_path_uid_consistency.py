#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from collections import defaultdict
from pathlib import Path

import civ1_authored_skin_integrity as skin
import civ1_external_resource_header_schema as header
import civ1_external_resource_uid_path_consistency as uid_path

SCHEMA = "grand-bruxelles-civ1-external-resource-path-uid-consistency-v1"


def path_uid_conflicts(declarations: list[dict[str, object]]) -> list[dict[str, object]]:
    by_path: dict[str, list[dict[str, object]]] = defaultdict(list)
    for row in declarations:
        by_path[str(row["path"])].append(row)

    conflicts: list[dict[str, object]] = []
    for path, rows in sorted(by_path.items()):
        uids = sorted({str(row["uid"]) for row in rows})
        if len(uids) <= 1:
            continue
        conflicts.append({
            "path": path,
            "uids": uids,
            "uid_count": len(uids),
            "declarations": rows,
            "reason": "same_resource_path_maps_to_multiple_uids",
        })
    return conflicts


def legacy_uid_path_chain_accepts(scene_text: str) -> bool:
    if not uid_path.legacy_header_chain_accepts(scene_text):
        return False
    declarations = uid_path.uid_path_declarations(scene_text)
    return uid_path.uid_path_conflicts(declarations) == []


def self_test() -> None:
    path = "res://assets/body.skin"
    canonical = f'''
[gd_scene format=3]
[ext_resource type="Skin" uid="uid://civ1skin" path="{path}" id="Skin_body"]
[node name="Main" type="Node3D"]
'''
    assert legacy_uid_path_chain_accepts(canonical)
    rows = uid_path.uid_path_declarations(canonical)
    assert path_uid_conflicts(rows) == []

    collision = canonical + f'\n[ext_resource type="Skin" uid="uid://civ1skinb" path="{path}" id="Skin_copy"]\n'
    assert header.uid_text_is_lexically_canonical("uid://civ1skin")
    assert header.uid_text_is_lexically_canonical("uid://civ1skinb")
    assert legacy_uid_path_chain_accepts(collision), (
        "causal precondition: retained header and one-UID-to-one-path gates accept two canonical UIDs on one path"
    )
    conflicts = path_uid_conflicts(uid_path.uid_path_declarations(collision))
    assert len(conflicts) == 1
    assert conflicts[0]["path"] == path
    assert conflicts[0]["uids"] == ["uid://civ1skin", "uid://civ1skinb"]

    repeated_same_uid = canonical + f'\n[ext_resource type="Skin" uid="uid://civ1skin" path="{path}" id="Skin_copy"]\n'
    assert path_uid_conflicts(uid_path.uid_path_declarations(repeated_same_uid)) == []


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        self_test()
        print("CIV1_EXTERNAL_RESOURCE_PATH_UID_CONSISTENCY_SELF_TEST_OK")
        return 0
    if len(sys.argv) != 3:
        print("usage: civ1_external_resource_path_uid_consistency.py MAIN_TSCN OUT", file=sys.stderr)
        return 2

    main_tscn = Path(sys.argv[1]).resolve()
    out_path = Path(sys.argv[2])
    project_root = main_tscn.parent.parent
    scenes = skin.reachable_scenes(main_tscn, project_root)

    declarations: list[dict[str, object]] = []
    for scene_path in scenes:
        rel = scene_path.relative_to(project_root).as_posix()
        declarations.extend(uid_path.uid_path_declarations(scene_path.read_text(encoding="utf-8"), rel))

    conflicts = path_uid_conflicts(declarations)
    result = {
        "schema": SCHEMA,
        "evidence_mode": "reachable_tscn_plus_project_scope_single_canonical_resource_uid_per_path_mapping",
        "reachable_scene_count": len(scenes),
        "external_resource_uid_declaration_count": len(declarations),
        "external_resource_path_uid_conflicts": conflicts,
        "external_resource_paths_have_single_uid": not conflicts,
        "external_resource_path_uid_collision_evidence_accepted": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "contact_verified": False,
        "foot_slide_verified": False,
        "next_action": "retain project-scope one-path-to-one-UID provenance before authored Character loaded-scene approval" if not conflicts else "resolve conflicting ResourceUID identities for the same resource path before Character provenance can be trusted",
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
