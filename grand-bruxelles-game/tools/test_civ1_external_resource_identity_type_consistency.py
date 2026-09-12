#!/usr/bin/env python3
from __future__ import annotations

import civ1_external_resource_header_schema as header
import civ1_external_resource_identity_type_consistency as gate
import civ1_external_resource_path_uid_consistency as path_uid
import civ1_external_resource_uid_path_consistency as uid_path
import civ1_resource_table_uniqueness as table


def main() -> int:
    uid = "uid://civ1skin"
    path = "res://assets/body.skin"

    forged_no_uid = f'''
[gd_scene format=3]
[ext_resource type="Skin" path="{path}" id="Skin_body"]
[ext_resource type="Texture2D" path="{path}" id="Skin_alias"]
[node name="Main" type="Node3D"]
'''

    ids, attrs, syntax, malformed = table.resource_table_conflicts(forged_no_uid)
    assert ids == [] and attrs == [] and syntax == [] and malformed == [], (
        "causal precondition: local IDs stay unique and both no-UID ext_resource headers parse"
    )
    assert header.external_resource_header_conflicts(forged_no_uid) == [], (
        "causal precondition: both conflicting no-UID declarations are individually canonical"
    )

    uid_rows = uid_path.uid_path_declarations(forged_no_uid, "fixture.tscn")
    assert uid_rows == [], (
        "causal precondition: retained UID identity gates do not observe declarations without ResourceUID"
    )
    assert uid_path.uid_path_conflicts(uid_rows) == []
    assert path_uid.path_uid_conflicts(uid_rows) == []

    rows = gate.external_resource_declarations(forged_no_uid, "fixture.tscn")
    assert gate.legacy_v1_conflicts(rows) == [], (
        "RED proof: v1 accepted one no-UID path declared as two Godot resource types"
    )
    conflicts = gate.identity_type_conflicts(rows)
    assert len(conflicts) == 1
    conflict = conflicts[0]
    assert conflict["path"] == path
    assert conflict["uids"] == []
    assert conflict["type_count"] == 2
    assert conflict["types"] == ["Skin", "Texture2D"]
    assert conflict["reason"] == "same_resource_path_declared_with_multiple_types"

    forged_uid = f'''
[gd_scene format=3]
[ext_resource type="Skin" uid="{uid}" path="{path}" id="Skin_body"]
[ext_resource type="Texture2D" uid="{uid}" path="{path}" id="Skin_alias"]
[node name="Main" type="Node3D"]
'''
    uid_conflicts = gate.identity_type_conflicts(gate.external_resource_declarations(forged_uid, "fixture.tscn"))
    assert len(uid_conflicts) == 1
    assert uid_conflicts[0]["uids"] == [uid]

    safe = forged_no_uid.replace('type="Texture2D"', 'type="Skin"')
    assert gate.identity_type_conflicts(gate.external_resource_declarations(safe, "fixture.tscn")) == []

    print("CIV1_EXTERNAL_RESOURCE_IDENTITY_TYPE_CONSISTENCY_REGRESSION_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
