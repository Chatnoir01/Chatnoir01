#!/usr/bin/env python3
from __future__ import annotations

import civ1_external_resource_identity_type_consistency as identity_type
import civ1_external_resource_path_uid_consistency as path_uid
import civ1_external_resource_uid_path_consistency as uid_path
import civ1_external_resource_uid_presence_consistency as target


uid = "uid://civ1skin"
path = "res://assets/body.skin"
scene = f'''
[gd_scene format=3]
[ext_resource type="Skin" uid="{uid}" path="{path}" id="Skin_body"]
[ext_resource type="Skin" path="{path}" id="Skin_copy"]
[node name="Main" type="Node3D"]
'''

assert uid_path.legacy_header_chain_accepts(scene), "retained resource-table/header schema must accept optional uid on both declarations"
uid_rows = uid_path.uid_path_declarations(scene)
assert len(uid_rows) == 1, "causal precondition: the no-UID declaration is invisible to UID-mapping gates"
assert uid_path.uid_path_conflicts(uid_rows) == []
assert path_uid.path_uid_conflicts(uid_rows) == []
assert identity_type.identity_type_conflicts(uid_rows) == []

rows = target.external_resource_declarations(scene)
assert len(rows) == 2
conflicts = target.uid_presence_conflicts(rows)
assert len(conflicts) == 1
conflict = conflicts[0]
assert conflict["path"] == path
assert conflict["uid_present_count"] == 1
assert conflict["uid_absent_count"] == 1

print("CIV1_EXTERNAL_RESOURCE_UID_PRESENCE_CAUSAL_REGRESSION_OK")
