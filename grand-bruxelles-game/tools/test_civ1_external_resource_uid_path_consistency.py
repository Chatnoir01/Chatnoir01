#!/usr/bin/env python3
from __future__ import annotations

import civ1_external_resource_header_schema as header
import civ1_external_resource_uid_path_consistency as gate
import civ1_resource_table_uniqueness as table


def main() -> int:
    uid = "uid://civ1skin"
    forged = f'''
[gd_scene format=3]
[ext_resource type="Skin" uid="{uid}" path="res://assets/body.skin" id="Skin_body"]
[ext_resource type="Texture2D" uid="{uid}" path="res://assets/body.png" id="Tex_body"]
[node name="Main" type="Node3D"]
'''

    ids, attrs, syntax, malformed = table.resource_table_conflicts(forged)
    assert ids == [] and attrs == [] and syntax == [] and malformed == [], (
        "causal precondition: local resource IDs remain unique"
    )
    assert header.external_resource_header_conflicts(forged) == [], (
        "causal precondition: both headers are individually canonical"
    )
    assert header.uid_text_is_lexically_canonical(uid)

    rows = gate.uid_path_declarations(forged, "fixture.tscn")
    conflicts = gate.uid_path_conflicts(rows)
    assert len(conflicts) == 1
    conflict = conflicts[0]
    assert conflict["uid"] == uid
    assert conflict["path_count"] == 2
    assert conflict["paths"] == ["res://assets/body.png", "res://assets/body.skin"]
    assert conflict["reason"] == "same_resource_uid_maps_to_multiple_paths"

    safe = forged.replace(
        f'uid="{uid}" path="res://assets/body.png" id="Tex_body"',
        'uid="uid://civ1tex" path="res://assets/body.png" id="Tex_body"',
    )
    assert gate.uid_path_conflicts(gate.uid_path_declarations(safe, "fixture.tscn")) == []

    print("CIV1_EXTERNAL_RESOURCE_UID_PATH_CONSISTENCY_REGRESSION_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
