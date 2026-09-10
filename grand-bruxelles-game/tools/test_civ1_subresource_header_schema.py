#!/usr/bin/env python3
from __future__ import annotations

import civ1_resource_table_uniqueness as table


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

    for text in (canonical,):
        ids, attrs, syntax, malformed = table.resource_table_conflicts(text)
        assert ids == [] and attrs == [] and syntax == [] and malformed == []

    # Causal RED against resource-table v5: all four malformed/ambiguous
    # sub_resource headers are currently fully parsed and accepted.
    for text in (forged_uid, forged_path, missing_type, missing_id):
        ids, attrs, syntax, malformed = table.resource_table_conflicts(text)
        assert ids == [] and attrs == []
        assert syntax or malformed, "sub_resource header schema violation was accepted"

    print("CIV1_SUBRESOURCE_HEADER_SCHEMA_TEST_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
