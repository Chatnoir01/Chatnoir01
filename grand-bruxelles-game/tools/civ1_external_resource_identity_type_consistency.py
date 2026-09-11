#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from collections import defaultdict
from pathlib import Path

import civ1_authored_skin_integrity as skin
import civ1_external_resource_header_schema as header
import civ1_external_resource_path_uid_consistency as path_uid
import civ1_external_resource_uid_path_consistency as uid_path
import civ1_resource_table_uniqueness as table

SCHEMA = "grand-bruxelles-civ1-external-resource-identity-type-consistency-v2"


def external_resource_declarations(scene_text: str, scene: str = "<memory>") -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for line_number, line in enumerate(scene_text.splitlines(), start=1):
        match = table.EXT_RE.match(line)
        if not match:
            continue
        pairs, residue = table.parse_header_attributes(match.group(1))
        attrs = dict(pairs)
        if residue or header.external_resource_header_conflicts(line):
            continue
        path = attrs.get("path")
        rid = attrs.get("id")
        resource_type = attrs.get("type")
        if not path or not rid or not resource_type:
            continue
        rows.append({
            "scene": scene,
            "line": line_number,
            "path": path,
            "id": rid,
            "type": resource_type,
            "uid": attrs.get("uid"),
            "uid_present": "uid" in attrs,
        })
    return rows


def optional_uid(row: dict[str, object]) -> str | None:
    value = row.get("uid")
    if not isinstance(value, str) or not value:
        return None
    return value


def identity_type_conflicts(declarations: list[dict[str, object]]) -> list[dict[str, object]]:
    by_path: dict[str, list[dict[str, object]]] = defaultdict(list)
    for row in declarations:
        path = str(row.get("path", ""))
        if not path:
            continue
        by_path[path].append(row)

    conflicts: list[dict[str, object]] = []
    for path, rows in sorted(by_path.items()):
        types = sorted({str(row.get("type", "")) for row in rows if str(row.get("type", ""))})
        if len(types) <= 1:
            continue
        uids = sorted({uid for row in rows if (uid := optional_uid(row)) is not None})
        conflicts.append({
            "path": path,
            "uids": uids,
            "types": types,
            "type_count": len(types),
            "declarations": rows,
            "reason": "same_resource_path_declared_with_multiple_types",
        })
    return conflicts


def retained_identity_chain_accepts(scene_text: str) -> bool:
    if not uid_path.legacy_header_chain_accepts(scene_text):
        return False
    uid_rows = uid_path.uid_path_declarations(scene_text)
    return (
        uid_path.uid_path_conflicts(uid_rows) == []
        and path_uid.path_uid_conflicts(uid_rows) == []
    )


def legacy_v1_conflicts(declarations: list[dict[str, object]]) -> list[dict[str, object]]:
    by_identity: dict[tuple[str, str], list[dict[str, object]]] = defaultdict(list)
    for row in declarations:
        uid = optional_uid(row)
        path = str(row.get("path", ""))
        if uid is None or not path:
            continue
        by_identity[(uid, path)].append(row)
    conflicts: list[dict[str, object]] = []
    for (uid, path), rows in sorted(by_identity.items()):
        types = sorted({str(row.get("type", "")) for row in rows if str(row.get("type", ""))})
        if len(types) > 1:
            conflicts.append({"uid": uid, "path": path, "types": types})
    return conflicts


def self_test() -> None:
    uid = "uid://civ1skin"
    path = "res://assets/body.skin"
    canonical = f'''
[gd_scene format=3]
[ext_resource type="Skin" uid="{uid}" path="{path}" id="Skin_body"]
[node name="Main" type="Node3D"]
'''
    assert retained_identity_chain_accepts(canonical)
    rows = external_resource_declarations(canonical)
    assert identity_type_conflicts(rows) == []

    conflicting_uid = canonical + f'\n[ext_resource type="Texture2D" uid="{uid}" path="{path}" id="Skin_alias"]\n'
    assert retained_identity_chain_accepts(conflicting_uid)
    conflicts = identity_type_conflicts(external_resource_declarations(conflicting_uid))
    assert len(conflicts) == 1
    assert conflicts[0]["path"] == path
    assert conflicts[0]["types"] == ["Skin", "Texture2D"]

    conflicting_no_uid = f'''
[gd_scene format=3]
[ext_resource type="Skin" path="{path}" id="Skin_body"]
[ext_resource type="Texture2D" path="{path}" id="Skin_alias"]
[node name="Main" type="Node3D"]
'''
    no_uid_rows = external_resource_declarations(conflicting_no_uid)
    assert legacy_v1_conflicts(no_uid_rows) == [], (
        "causal precondition: v1 ignored type collisions when ResourceUID was absent"
    )
    conflicts = identity_type_conflicts(no_uid_rows)
    assert len(conflicts) == 1
    assert conflicts[0]["path"] == path
    assert conflicts[0]["uids"] == []
    assert conflicts[0]["types"] == ["Skin", "Texture2D"]

    repeated_same_type = canonical + f'\n[ext_resource type="Skin" uid="{uid}" path="{path}" id="Skin_copy"]\n'
    assert identity_type_conflicts(external_resource_declarations(repeated_same_type)) == []


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        self_test()
        print("CIV1_EXTERNAL_RESOURCE_IDENTITY_TYPE_CONSISTENCY_SELF_TEST_OK")
        return 0
    if len(sys.argv) != 3:
        print("usage: civ1_external_resource_identity_type_consistency.py MAIN_TSCN OUT", file=sys.stderr)
        return 2

    main_tscn = Path(sys.argv[1]).resolve()
    out_path = Path(sys.argv[2])
    project_root = main_tscn.parent.parent
    scenes = skin.reachable_scenes(main_tscn, project_root)

    declarations: list[dict[str, object]] = []
    for scene_path in scenes:
        rel = scene_path.relative_to(project_root).as_posix()
        declarations.extend(external_resource_declarations(scene_path.read_text(encoding="utf-8"), rel))

    conflicts = identity_type_conflicts(declarations)
    result = {
        "schema": SCHEMA,
        "evidence_mode": "reachable_tscn_plus_project_scope_single_declared_type_per_canonical_external_resource_path_with_or_without_uid",
        "reachable_scene_count": len(scenes),
        "external_resource_declaration_count": len(declarations),
        "external_resource_identity_type_conflicts": conflicts,
        "external_resource_paths_have_single_type": not conflicts,
        "external_resource_no_uid_type_collision_evidence_accepted": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "contact_verified": False,
        "foot_slide_verified": False,
        "next_action": "retain one declared Godot type per canonical external-resource path before authored Character loaded-scene approval" if not conflicts else "resolve conflicting declared types for the same canonical external-resource path before Character provenance can be trusted",
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
