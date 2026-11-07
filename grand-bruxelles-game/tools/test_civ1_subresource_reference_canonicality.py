#!/usr/bin/env python3
from __future__ import annotations

import civ1_subresource_reference_canonicality as canonical
import civ1_subresource_reference_order as order


def main() -> int:
    base = '''
[gd_scene format=3]
[sub_resource type="StandardMaterial3D" id="Mat_body"]
[sub_resource type="ArrayMesh" id="Mesh_body"]
surface_0/material = SubResource("Mat_body")
[node name="Main" type="Node3D"]
'''

    escaped = base.replace('SubResource("Mat_body")', 'SubResource("Mat\\u005fbody")')
    assert order.subresource_reference_order_conflicts(escaped) == [], "legacy order gate must reproduce escaped-ID false positive"
    escaped_conflicts = canonical.subresource_reference_canonicality_conflicts(escaped)
    assert len(escaped_conflicts) == 1
    assert escaped_conflicts[0]["reason"] == "escaped_subresource_reference_id_alias"

    spaced = base.replace('SubResource("Mat_body")', 'SubResource( "Mat_body" )')
    assert order.subresource_reference_order_conflicts(spaced) == [], "legacy regex must reproduce whitespace blind spot"
    spaced_conflicts = canonical.subresource_reference_canonicality_conflicts(spaced)
    assert len(spaced_conflicts) == 1
    assert spaced_conflicts[0]["reason"] == "subresource_reference_whitespace_or_missing_quote"

    assert canonical.subresource_reference_canonicality_conflicts(base) == []
    print("CIV1_SUBRESOURCE_REFERENCE_CANONICALITY_CAUSAL_RED_GREEN_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
