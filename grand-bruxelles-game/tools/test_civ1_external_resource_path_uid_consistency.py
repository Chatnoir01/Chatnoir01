#!/usr/bin/env python3
from __future__ import annotations

import civ1_external_resource_header_schema as header
import civ1_external_resource_path_uid_consistency as gate
import civ1_external_resource_uid_path_consistency as uid_path
import civ1_resource_table_uniqueness as table


def main() -> int:
    path = "res://assets/body.skin"
    uid_a = "uid://civ1skin"
    uid_b = "uid://civ1skinb"
    forged = f'''
[gd_scene format=3]
[ext_resource type="Skin" uid="{uid_a}" path="{path}" id="Skin_body"]
[ext_resource type="Skin" uid="{uid_b}" path="{path}" id="Skin_copy"]
[node name="Main" type="Node3D"]
'''

    ids, attrs, syntax, malformed = table.resource_table_conflicts(forged)
    assert ids == [] and attrs == [] and syntax == [] and malformed == [], (
        "causal precondition: local resource IDs remain unique and headers parse"
    )
    assert header.external_resource_header_conflicts(forged) == [], (
        "causal precondition: both external-resource headers are individually canonical"
    )
    assert header.uid_text_is_lexically_canonical(uid_a)
    assert header.uid_text_is_lexically_canonical(uid_b)

    rows = uid_path.uid_path_declarations(forged, "fixture.tscn")
    assert uid_path.uid_path_conflicts(rows) == [], (
        "causal precondition: retained one-UID-to-one-path gate does not detect the inverse ambiguity"
    )

    conflicts = gate.path_uid_conflicts(rows)
    assert len(conflicts) == 1
    conflict = conflicts[0]
    assert conflict["path"] == path
    assert conflict["uid_count"] == 2
    assert conflict["uids"] == [uid_a, uid_b]
    assert conflict["reason"] == "same_resource_path_maps_to_multiple_uids"

    safe = forged.replace(uid_b, uid_a)
    safe_rows = uid_path.uid_path_declarations(safe, "fixture.tscn")
    assert gate.path_uid_conflicts(safe_rows) == []

    print("CIV1_EXTERNAL_RESOURCE_PATH_UID_CONSISTENCY_REGRESSION_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
