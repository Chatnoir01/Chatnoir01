#!/usr/bin/env python3
from __future__ import annotations

import civ1_authored_skin_integrity as skin
import civ1_external_resource_header_schema as gate
import civ1_resource_table_uniqueness as table


def main() -> int:
    canonical_uid = "uid://civ1skin"
    canonical = f'''
[gd_scene format=3]
[ext_resource type="Skin" uid="{canonical_uid}" path="res://assets/body.skin" id="Skin_body"]
[node name="Main" type="Node3D"]
'''
    forged = canonical.replace(' id="Skin_body"]', ' evidence="forged" id="Skin_body"]')

    ids, attrs, syntax, malformed = table.resource_table_conflicts(forged)
    assert ids == [] and attrs == [] and syntax == [] and malformed == [], (
        "regression precondition: retained resource-table uniqueness must expose the foreign-attribute blind spot"
    )
    parsed = skin.parse_resource_table(forged)
    assert parsed[("ExtResource", "Skin_body")]["type"] == "Skin"
    assert parsed[("ExtResource", "Skin_body")]["path"] == "res://assets/body.skin"

    conflicts = gate.external_resource_header_conflicts(forged)
    assert len(conflicts) == 1
    assert "foreign_header_attribute" in conflicts[0]["reasons"]
    assert conflicts[0]["foreign_attributes"] == ["evidence"]

    malformed_uid = "uid://NOT_VALID"
    malformed_uid_scene = canonical.replace(canonical_uid, malformed_uid)
    parsed_uid_scene = skin.parse_resource_table(malformed_uid_scene)
    ext = parsed_uid_scene[("ExtResource", "Skin_body")]
    assert ext["type"] == "Skin" and ext["path"] == "res://assets/body.skin"
    assert gate.legacy_uid_prefix_evidence_accepted(malformed_uid), (
        "causal precondition: v1 accepted any non-empty uid:// prefix"
    )
    uid_conflicts = gate.external_resource_header_conflicts(malformed_uid_scene)
    assert len(uid_conflicts) == 1
    assert "invalid_uid_attribute" in uid_conflicts[0]["reasons"]
    assert uid_conflicts[0]["invalid_uid"] is True

    # v2 still accepted these lowercase/digit strings, but Godot's ResourceUID
    # decoder maps them to a different canonical text (leading-zero aliases and
    # the parser-only z/9 spellings included).
    aliases = {
        "uid://abc": "uid://bc",
        "uid://z": "uid://0",
        "uid://9": "uid://ba",
        "uid://aciv1skin": canonical_uid,
    }
    for alias, expected_canonical in aliases.items():
        assert gate.legacy_uid_regex_evidence_accepted(alias), (
            f"causal precondition: v2 regex must accept {alias}"
        )
        uid = gate._godot_uid_text_to_id(alias)
        assert uid is not None
        assert gate._godot_uid_id_to_text(uid) == expected_canonical
        assert expected_canonical != alias
        alias_scene = canonical.replace(canonical_uid, alias)
        parsed_alias = skin.parse_resource_table(alias_scene)
        assert parsed_alias[("ExtResource", "Skin_body")]["type"] == "Skin"
        alias_conflicts = gate.external_resource_header_conflicts(alias_scene)
        assert len(alias_conflicts) == 1
        assert "invalid_uid_attribute" in alias_conflicts[0]["reasons"]
        assert alias_conflicts[0]["invalid_uid"] is True

    assert gate.uid_text_is_lexically_canonical(canonical_uid)
    assert gate.external_resource_header_conflicts(canonical) == []
    print("CIV1_EXTERNAL_RESOURCE_HEADER_SCHEMA_REGRESSION_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
