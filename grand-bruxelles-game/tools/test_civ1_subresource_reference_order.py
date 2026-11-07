#!/usr/bin/env python3
from __future__ import annotations

import civ1_authored_skin_integrity as skin
import civ1_subresource_reference_order as order


def main() -> int:
    canonical = '''
[gd_scene format=3]
[sub_resource type="StandardMaterial3D" id="Mat_body"]
[sub_resource type="ArrayMesh" id="Mesh_body"]
surface_0/material = SubResource("Mat_body")
[node name="Main" type="Node3D"]
'''
    assert order.subresource_reference_order_conflicts(canonical) == []

    forward = '''
[gd_scene format=3]
[sub_resource type="ArrayMesh" id="Mesh_body"]
surface_0/material = SubResource("Mat_body")
[sub_resource type="StandardMaterial3D" id="Mat_body"]
[node name="Main" type="Node3D"]
'''
    legacy = skin.parse_resource_table(forward)
    assert legacy[("SubResource", "Mat_body")]["type"] == "StandardMaterial3D"
    conflicts = order.subresource_reference_order_conflicts(forward)
    assert len(conflicts) == 1
    assert conflicts[0]["owner_subresource_id"] == "Mesh_body"
    assert conflicts[0]["referenced_subresource_id"] == "Mat_body"
    assert conflicts[0]["reason"] == "missing_or_forward_subresource_reference"

    missing = canonical.replace('SubResource("Mat_body")', 'SubResource("MissingMat")')
    conflicts = order.subresource_reference_order_conflicts(missing)
    assert len(conflicts) == 1
    assert conflicts[0]["referenced_subresource_id"] == "MissingMat"

    print("CIV1_SUBRESOURCE_REFERENCE_ORDER_REGRESSION_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
