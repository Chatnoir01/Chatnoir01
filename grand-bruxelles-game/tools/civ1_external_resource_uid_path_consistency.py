#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from collections import defaultdict
from pathlib import Path

import civ1_authored_skin_integrity as skin
import civ1_external_resource_header_schema as header
import civ1_resource_table_uniqueness as table

SCHEMA = "grand-bruxelles-civ1-external-resource-uid-path-consistency-v1"


def uid_path_declarations(scene_text: str, scene: str = "<memory>") -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for line_number, line in enumerate(scene_text.splitlines(), start=1):
        match = table.EXT_RE.match(line)
        if not match:
            continue
        pairs, residue = table.parse_header_attributes(match.group(1))
        attrs = dict(pairs)
        uid = attrs.get("uid")
        path = attrs.get("path")
        rid = attrs.get("id")
        if residue or not uid or not path or not rid:
            continue
        if not header.uid_text_is_lexically_canonical(uid):
            continue
        rows.append({
            "scene": scene,
            "line": line_number,
            "uid": uid,
            "path": path,
            "id": rid,
            "type": attrs.get("type", ""),
        })
    return rows


def uid_path_conflicts(declarations: list[dict[str, object]]) -> list[dict[str, object]]:
    by_uid: dict[str, list[dict[str, object]]] = defaultdict(list)
    for row in declarations:
        by_uid[str(row["uid"])].append(row)

    conflicts: list[dict[str, object]] = []
    for uid, rows in sorted(by_uid.items()):
        paths = sorted({str(row["path"]) for row in rows})
        if len(paths) <= 1:
            continue
        conflicts.append({
            "uid": uid,
            "paths": paths,
            "path_count": len(paths),
            "declarations": rows,
            "reason": "same_resource_uid_maps_to_multiple_paths",
        })
    return conflicts


def legacy_header_chain_accepts(scene_text: str) -> bool:
    ids, attrs, syntax, malformed = table.resource_table_conflicts(scene_text)
    return (
        not ids
        and not attrs
        and not syntax
        and not malformed
        and header.external_resource_header_conflicts(scene_text) == []
    )


def self_test() -> None:
    uid = "uid://civ1skin"
    canonical = f'''
[gd_scene format=3]
[ext_resource type="Skin" uid="{uid}" path="res://assets/body.skin" id="Skin_body"]
[ext_resource type="Texture2D" uid="uid://civ1tex" path="res://assets/body.png" id="Tex_body"]
[node name="Main" type="Node3D"]
'''
    assert legacy_header_chain_accepts(canonical)
    rows = uid_path_declarations(canonical)
    assert uid_path_conflicts(rows) == []

    collision = canonical.replace(
        '[ext_resource type="Texture2D" uid="uid://civ1tex" path="res://assets/body.png" id="Tex_body"]',
        f'[ext_resource type="Texture2D" uid="{uid}" path="res://assets/body.png" id="Tex_body"]',
    )
    assert legacy_header_chain_accepts(collision), (
        "causal precondition: retained resource-table/header gates accept one canonical UID on two distinct paths"
    )
    conflicts = uid_path_conflicts(uid_path_declarations(collision))
    assert len(conflicts) == 1
    assert conflicts[0]["uid"] == uid
    assert conflicts[0]["paths"] == ["res://assets/body.png", "res://assets/body.skin"]

    repeated_same_path = canonical + f'\n[ext_resource type="Skin" uid="{uid}" path="res://assets/body.skin" id="Skin_copy"]\n'
    assert uid_path_conflicts(uid_path_declarations(repeated_same_path)) == []


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        self_test()
        print("CIV1_EXTERNAL_RESOURCE_UID_PATH_CONSISTENCY_SELF_TEST_OK")
        return 0
    if len(sys.argv) != 3:
        print("usage: civ1_external_resource_uid_path_consistency.py MAIN_TSCN OUT", file=sys.stderr)
        return 2

    main_tscn = Path(sys.argv[1]).resolve()
    out_path = Path(sys.argv[2])
    project_root = main_tscn.parent.parent
    scenes = skin.reachable_scenes(main_tscn, project_root)

    declarations: list[dict[str, object]] = []
    for scene_path in scenes:
        rel = scene_path.relative_to(project_root).as_posix()
        declarations.extend(uid_path_declarations(scene_path.read_text(encoding="utf-8"), rel))

    conflicts = uid_path_conflicts(declarations)
    result = {
        "schema": SCHEMA,
        "evidence_mode": "reachable_tscn_plus_project_scope_canonical_resource_uid_to_single_path_mapping",
        "reachable_scene_count": len(scenes),
        "external_resource_uid_declaration_count": len(declarations),
        "external_resource_uid_path_conflicts": conflicts,
        "external_resource_uid_paths_unambiguous": not conflicts,
        "external_resource_uid_path_collision_evidence_accepted": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "contact_verified": False,
        "foot_slide_verified": False,
        "next_action": "retain project-scope one-UID-to-one-path provenance before authored Character loaded-scene approval" if not conflicts else "resolve conflicting resource UID path mappings before Character provenance can be trusted",
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
