#!/usr/bin/env python3
from __future__ import annotations

import civ1_resource_table_uniqueness as legacy
import civ1_subresource_header_schema as gate


def main() -> int:
    canonical = '''
[gd_scene format=3]
[sub_resource type="Skin" id="Skin_body"]
[node name="Main" type="Node3D"]
'''
    forged_uid = canonical.replace(
        '[sub_resource type="Skin" id="Skin_body"]',
        '[sub_resource type="Skin" uid="uid://forged" id="Skin_body"]',
    )
    forged_path = canonical.replace(
        '[sub_resource type="Skin" id="Skin_body"]',
        '[sub_resource type="Skin" path="res://forged.skin" id="Skin_body"]',
    )
    missing_type = canonical.replace(
        '[sub_resource type="Skin" id="Skin_body"]',
        '[sub_resource id="Skin_body"]',
    )
    missing_id = canonical.replace(
        '[sub_resource type="Skin" id="Skin_body"]',
        '[sub_resource type="Skin"]',
    )

    assert gate.subresource_header_conflicts(canonical) == []

    # Preserve the causal witness: resource-table v5 fully parses these
    # headers and reports no conflict, so the new closed-schema gate is needed.
    for text in (forged_uid, forged_path, missing_type, missing_id):
        ids, attrs, syntax, malformed = legacy.resource_table_conflicts(text)
        assert ids == [] and attrs == [] and syntax == [] and malformed == []
        conflicts = gate.subresource_header_conflicts(text)
        assert len(conflicts) == 1

    gate.self_test()
    print("CIV1_SUBRESOURCE_HEADER_SCHEMA_TEST_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
