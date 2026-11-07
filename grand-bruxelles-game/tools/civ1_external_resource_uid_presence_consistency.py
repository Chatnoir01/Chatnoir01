#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from collections import defaultdict
from pathlib import Path

import civ1_authored_skin_integrity as skin
import civ1_external_resource_header_schema as header
import civ1_external_resource_identity_type_consistency as identity_type
import civ1_external_resource_path_uid_consistency as path_uid
import civ1_external_resource_uid_path_consistency as uid_path
import civ1_resource_table_uniqueness as table

SCHEMA = "grand-bruxelles-civ1-external-resource-uid-presence-consistency-v1"


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


def uid_presence_conflicts(declarations: list[dict[str, object]]) -> list[dict[str, object]]:
    by_path: dict[str, list[dict[str, object]]] = defaultdict(list)
    for row in declarations:
        by_path[str(row["path"])].append(row)

    conflicts: list[dict[str, object]] = []
    for path, rows in sorted(by_path.items()):
        presence = {bool(row.get("uid_present")) for row in rows}
        if len(presence) <= 1:
            continue
        conflicts.append({
            "path": path,
            "uid_present_count": sum(bool(row.get("uid_present")) for row in rows),
            "uid_absent_count": sum(not bool(row.get("uid_present")) for row in rows),
            "declarations": rows,
            "reason": "same_resource_path_mixes_uid_present_and_uid_absent_declarations",
        })
    return conflicts


def retained_identity_chain_accepts(scene_text: str) -> bool:
    if not uid_path.legacy_header_chain_accepts(scene_text):
        return False
    uid_rows = uid_path.uid_path_declarations(scene_text)
    return (
        uid_path.uid_path_conflicts(uid_rows) == []
        and path_uid.path_uid_conflicts(uid_rows) == []
        and identity_type.identity_type_conflicts(uid_rows) == []
    )


def self_test() -> None:
    uid = "uid://civ1skin"
    path = "res://assets/body.skin"
    canonical = f'''
[gd_scene format=3]
[ext_resource type="Skin" uid="{uid}" path="{path}" id="Skin_body"]
[node name="Main" type="Node3D"]
'''
    assert retained_identity_chain_accepts(canonical)
    assert uid_presence_conflicts(external_resource_declarations(canonical)) == []

    mixed = canonical + f'\n[ext_resource type="Skin" path="{path}" id="Skin_copy"]\n'
    assert retained_identity_chain_accepts(mixed), (
        "causal precondition: retained header/UID-path/type gates ignore the no-UID alias for the same canonical path"
    )
    conflicts = uid_presence_conflicts(external_resource_declarations(mixed))
    assert len(conflicts) == 1
    assert conflicts[0]["path"] == path
    assert conflicts[0]["uid_present_count"] == 1
    assert conflicts[0]["uid_absent_count"] == 1

    all_without_uid = f'''
[gd_scene format=3]
[ext_resource type="Skin" path="{path}" id="Skin_body"]
[ext_resource type="Skin" path="{path}" id="Skin_copy"]
[node name="Main" type="Node3D"]
'''
    assert retained_identity_chain_accepts(all_without_uid)
    assert uid_presence_conflicts(external_resource_declarations(all_without_uid)) == []

    repeated_uid = canonical + f'\n[ext_resource type="Skin" uid="{uid}" path="{path}" id="Skin_copy"]\n'
    assert retained_identity_chain_accepts(repeated_uid)
    assert uid_presence_conflicts(external_resource_declarations(repeated_uid)) == []


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        self_test()
        print("CIV1_EXTERNAL_RESOURCE_UID_PRESENCE_CONSISTENCY_SELF_TEST_OK")
        return 0
    if len(sys.argv) != 3:
        print("usage: civ1_external_resource_uid_presence_consistency.py MAIN_TSCN OUT", file=sys.stderr)
        return 2

    main_tscn = Path(sys.argv[1]).resolve()
    out_path = Path(sys.argv[2])
    project_root = main_tscn.parent.parent
    scenes = skin.reachable_scenes(main_tscn, project_root)

    declarations: list[dict[str, object]] = []
    for scene_path in scenes:
        rel = scene_path.relative_to(project_root).as_posix()
        declarations.extend(external_resource_declarations(scene_path.read_text(encoding="utf-8"), rel))

    conflicts = uid_presence_conflicts(declarations)
    result = {
        "schema": SCHEMA,
        "evidence_mode": "reachable_tscn_plus_project_scope_consistent_optional_resource_uid_presence_per_canonical_path",
        "reachable_scene_count": len(scenes),
        "external_resource_declaration_count": len(declarations),
        "external_resource_uid_presence_conflicts": conflicts,
        "external_resource_paths_have_consistent_uid_presence": not conflicts,
        "external_resource_mixed_uid_presence_evidence_accepted": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "contact_verified": False,
        "foot_slide_verified": False,
        "next_action": "retain consistent ResourceUID presence for each canonical external-resource path before authored Character loaded-scene approval" if not conflicts else "make ResourceUID presence consistent for every repeated external-resource path before Character provenance can be trusted",
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
