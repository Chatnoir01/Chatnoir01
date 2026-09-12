#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from collections import Counter
from pathlib import Path

import civ1_authored_skin_integrity as skin
import civ1_resource_table_uniqueness as table

SCHEMA = "grand-bruxelles-civ1-subresource-header-schema-v1"
REQUIRED_ATTRIBUTES = frozenset({"type", "id"})
ALLOWED_ATTRIBUTES = REQUIRED_ATTRIBUTES


def subresource_header_conflicts(scene_text: str) -> list[dict[str, object]]:
    conflicts: list[dict[str, object]] = []
    for line_number, line in enumerate(scene_text.splitlines(), start=1):
        match = table.SUB_RE.match(line)
        if not match:
            continue
        pairs, residue = table.parse_header_attributes(match.group(1))
        counts = Counter(name for name, _ in pairs)
        attrs = dict(pairs)
        names = set(attrs)
        reasons: list[str] = []
        if residue:
            reasons.append("unparsed_header_fragment")
        if any(count > 1 for count in counts.values()):
            reasons.append("duplicate_header_attribute")
        missing = sorted(REQUIRED_ATTRIBUTES - names)
        foreign = sorted(names - ALLOWED_ATTRIBUTES)
        empty = sorted(name for name in REQUIRED_ATTRIBUTES if name in attrs and not attrs[name])
        if missing:
            reasons.append("missing_required_attribute")
        if foreign:
            reasons.append("foreign_header_attribute")
        if empty:
            reasons.append("empty_required_attribute")
        if reasons:
            conflicts.append(
                {
                    "line": line_number,
                    "raw_header": line.strip(),
                    "reasons": reasons,
                    "missing_attributes": missing,
                    "foreign_attributes": foreign,
                    "empty_required_attributes": empty,
                }
            )
    return conflicts


def self_test() -> None:
    canonical = '''
[gd_scene format=3]
[sub_resource type="Skin" id="Skin_body"]
[node name="Main" type="Node3D"]
'''
    assert subresource_header_conflicts(canonical) == []
    cases = {
        "uid": '[sub_resource type="Skin" uid="uid://forged" id="Skin_body"]',
        "path": '[sub_resource type="Skin" path="res://forged.skin" id="Skin_body"]',
        "missing_type": '[sub_resource id="Skin_body"]',
        "missing_id": '[sub_resource type="Skin"]',
        "empty_type": '[sub_resource type="" id="Skin_body"]',
        "empty_id": '[sub_resource type="Skin" id=""]',
    }
    for label, header in cases.items():
        text = canonical.replace('[sub_resource type="Skin" id="Skin_body"]', header)
        conflicts = subresource_header_conflicts(text)
        assert len(conflicts) == 1, label
    # Godot keeps ExtResource and SubResource namespaces separate; this gate
    # intentionally constrains only sub_resource header schema.
    cross_kind = canonical.replace(
        '[sub_resource type="Skin" id="Skin_body"]',
        '[ext_resource type="Skin" uid="uid://ok" path="res://skin.tres" id="Skin_body"]\n[sub_resource type="Skin" id="Skin_body"]',
    )
    assert subresource_header_conflicts(cross_kind) == []


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        self_test()
        print("CIV1_SUBRESOURCE_HEADER_SCHEMA_SELF_TEST_OK")
        return 0
    if len(sys.argv) != 3:
        print("usage: civ1_subresource_header_schema.py MAIN_TSCN OUT", file=sys.stderr)
        return 2

    main_tscn = Path(sys.argv[1]).resolve()
    out_path = Path(sys.argv[2])
    project_root = main_tscn.parent.parent
    scenes = skin.reachable_scenes(main_tscn, project_root)
    conflicts: list[dict[str, object]] = []
    for scene_path in scenes:
        rel = scene_path.relative_to(project_root).as_posix()
        for conflict in subresource_header_conflicts(scene_path.read_text(encoding="utf-8")):
            conflicts.append({"scene": rel, **conflict})

    result = {
        "schema": SCHEMA,
        "evidence_mode": "reachable_tscn_plus_closed_subresource_header_attribute_schema",
        "reachable_scene_count": len(scenes),
        "subresource_header_schema_conflicts": conflicts,
        "subresource_header_schema_canonical": not conflicts,
        "subresource_uid_evidence_accepted": False,
        "subresource_path_evidence_accepted": False,
        "subresource_missing_required_attribute_evidence_accepted": False,
        "subresource_empty_required_attribute_evidence_accepted": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "contact_verified": False,
        "foot_slide_verified": False,
        "next_action": "retain closed type+id subresource headers before authored Character loaded-scene approval" if not conflicts else "remove foreign, missing, empty or ambiguous subresource header attributes before authored Character evidence can be trusted",
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
