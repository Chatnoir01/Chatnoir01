#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path

import civ1_authored_skin_integrity as skin
import civ1_external_resource_header_schema as header_schema
import civ1_resource_table_uniqueness as table

SCHEMA = "grand-bruxelles-civ1-external-resource-id-canonicality-v1"


def _canonical_quoted_payload(value: str) -> str:
    encoded = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    assert len(encoded) >= 2 and encoded[0] == '"' and encoded[-1] == '"'
    return encoded[1:-1]


def external_resource_id_conflicts(scene_text: str) -> list[dict[str, object]]:
    conflicts: list[dict[str, object]] = []
    for line_number, line in enumerate(scene_text.splitlines(), start=1):
        match = table.EXT_RE.match(line)
        if not match:
            continue
        for attr_match in table.ATTR_RE.finditer(match.group(1)):
            if attr_match.group(1) != "id":
                continue
            raw_id = attr_match.group(2)
            decoded_id = table._decode_quoted(raw_id)
            if decoded_id is None:
                conflicts.append({
                    "line": line_number,
                    "raw_header": line.strip(),
                    "raw_id": raw_id,
                    "decoded_id": None,
                    "canonical_id_payload": None,
                    "reason": "external_resource_id_invalid_escape",
                })
                continue
            canonical = _canonical_quoted_payload(decoded_id)
            if raw_id != canonical:
                conflicts.append({
                    "line": line_number,
                    "raw_header": line.strip(),
                    "raw_id": raw_id,
                    "decoded_id": decoded_id,
                    "canonical_id_payload": canonical,
                    "reason": "external_resource_id_noncanonical_lexeme",
                })
    return conflicts


def _fixture(id_payload: str, reference_payload: str) -> str:
    return f'''
[gd_scene load_steps=4 format=3]
[ext_resource type="Skin" path="res://assets/body.skin" id="{id_payload}"]
[sub_resource type="ArrayMesh" id="Mesh_body"]
[sub_resource type="StandardMaterial3D" id="Mat_body"]
[node name="Main" type="Node3D"]
[node name="NpcAgent" type="CharacterBody3D" parent="."]
[node name="CharacterMount" type="Node3D" parent="NpcAgent"]
[node name="Skeleton3D" type="Skeleton3D" parent="NpcAgent/CharacterMount"]
[node name="Body" type="MeshInstance3D" parent="NpcAgent/CharacterMount"]
skeleton = NodePath("../Skeleton3D")
mesh = SubResource("Mesh_body")
skin = ExtResource("{reference_payload}")
material_override = SubResource("Mat_body")
'''


def retained_blind_spot_accepts(scene_text: str) -> bool:
    ids, attrs, syntax, malformed = table.resource_table_conflicts(scene_text)
    header_conflicts = header_schema.external_resource_header_conflicts(scene_text)
    integrity = skin.scene_integrity(scene_text)
    return (
        not ids
        and not attrs
        and not syntax
        and not malformed
        and not header_conflicts
        and len(integrity) == 1
        and bool(integrity[0].get("authored_skin_integrity_ready"))
    )


def self_test() -> None:
    canonical = _fixture("Skin_body", "Skin_body")
    assert external_resource_id_conflicts(canonical) == []

    escaped_alias = _fixture(r"Skin\u005fbody", r"Skin\u005fbody")
    assert retained_blind_spot_accepts(escaped_alias), (
        "causal precondition: retained table/header/authored-skin evidence must accept the single escaped external-resource id"
    )
    conflicts = external_resource_id_conflicts(escaped_alias)
    assert len(conflicts) == 1
    assert conflicts[0]["decoded_id"] == "Skin_body"
    assert conflicts[0]["canonical_id_payload"] == "Skin_body"

    literal_unicode = _fixture("Peau_é", "Peau_é")
    assert external_resource_id_conflicts(literal_unicode) == []
    escaped_unicode = _fixture(r"Peau_\u00e9", r"Peau_\u00e9")
    assert external_resource_id_conflicts(escaped_unicode), "unicode escape aliases must not create a second spelling"


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        self_test()
        print("CIV1_EXTERNAL_RESOURCE_ID_CANONICALITY_SELF_TEST_OK")
        return 0
    if len(sys.argv) != 3:
        print("usage: civ1_external_resource_id_canonicality.py MAIN_TSCN OUT", file=sys.stderr)
        return 2

    main_tscn = Path(sys.argv[1]).resolve()
    out_path = Path(sys.argv[2])
    project_root = main_tscn.parent.parent
    scenes = skin.reachable_scenes(main_tscn, project_root)
    conflicts: list[dict[str, object]] = []
    for scene_path in scenes:
        rel = scene_path.relative_to(project_root).as_posix()
        for conflict in external_resource_id_conflicts(scene_path.read_text(encoding="utf-8")):
            conflicts.append({"scene": rel, **conflict})

    result = {
        "schema": SCHEMA,
        "evidence_mode": "reachable_tscn_plus_minimally_encoded_external_resource_id_lexemes",
        "reachable_scene_count": len(scenes),
        "external_resource_id_canonicality_conflicts": conflicts,
        "external_resource_id_lexemes_canonical": not conflicts,
        "escaped_external_resource_id_evidence_accepted": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "contact_verified": False,
        "foot_slide_verified": False,
        "next_action": (
            "retain minimally encoded external-resource ids before authored Character loaded-scene approval"
            if not conflicts
            else "replace escaped or otherwise noncanonical ext_resource id spellings before Character evidence can be trusted"
        ),
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
