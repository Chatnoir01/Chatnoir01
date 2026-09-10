#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from collections import Counter
from pathlib import Path

import civ1_authored_skin_integrity as skin

SCHEMA = "grand-bruxelles-civ1-resource-table-uniqueness-v4"
EXT_RE = re.compile(r'^\s*\[ext_resource\s+(.+?)\]\s*$')
SUB_RE = re.compile(r'^\s*\[sub_resource\s+(.+?)\]\s*$')
RESOURCE_PREFIX_RE = re.compile(r'^\s*\[(ext_resource|sub_resource)\b')
ATTR_RE = re.compile(r'\b([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"((?:\\.|[^"\\])*)"')


def parse_header_attributes(header: str) -> tuple[list[tuple[str, str]], str]:
    pairs: list[tuple[str, str]] = []
    cursor = 0
    residue: list[str] = []
    for match in ATTR_RE.finditer(header):
        between = header[cursor:match.start()]
        if between.strip():
            residue.append(between.strip())
        pairs.append((match.group(1), match.group(2)))
        cursor = match.end()
    tail = header[cursor:]
    if tail.strip():
        residue.append(tail.strip())
    return pairs, " ".join(residue)


def resource_table_conflicts(
    scene_text: str,
) -> tuple[
    list[dict[str, object]],
    list[dict[str, object]],
    list[dict[str, object]],
    list[dict[str, object]],
]:
    seen: dict[tuple[str, str], list[dict[str, str]]] = {}
    attribute_conflicts: list[dict[str, object]] = []
    syntax_conflicts: list[dict[str, object]] = []
    malformed_header_conflicts: list[dict[str, object]] = []

    for line_number, line in enumerate(scene_text.splitlines(), start=1):
        match = EXT_RE.match(line)
        kind = "ExtResource"
        if not match:
            match = SUB_RE.match(line)
            kind = "SubResource"
        if not match:
            prefix = RESOURCE_PREFIX_RE.match(line)
            if prefix:
                malformed_header_conflicts.append({
                    "kind": "ExtResource" if prefix.group(1) == "ext_resource" else "SubResource",
                    "line": line_number,
                    "raw_header": line.strip(),
                    "reason": "resource_header_did_not_match_complete_bracketed_grammar",
                })
            continue

        attr_pairs, residue = parse_header_attributes(match.group(1))
        if residue:
            syntax_conflicts.append({
                "kind": kind,
                "line": line_number,
                "unparsed_fragment": residue,
                "raw_header": line.strip(),
            })

        attr_counts = Counter(name for name, _ in attr_pairs)
        duplicate_attributes = sorted(name for name, count in attr_counts.items() if count > 1)
        if duplicate_attributes:
            attribute_conflicts.append({
                "kind": kind,
                "line": line_number,
                "duplicate_attributes": duplicate_attributes,
                "attribute_occurrences": {
                    name: attr_counts[name] for name in duplicate_attributes
                },
                "raw_header": line.strip(),
            })

        attrs = dict(attr_pairs)
        rid = attrs.get("id")
        if not rid:
            continue
        seen.setdefault((kind, rid), []).append({
            "line": str(line_number),
            "type": attrs.get("type", ""),
            "path": attrs.get("path", ""),
        })

    id_conflicts: list[dict[str, object]] = []
    for (kind, rid), declarations in sorted(seen.items()):
        if len(declarations) <= 1:
            continue
        id_conflicts.append({
            "kind": kind,
            "id": rid,
            "declaration_count": len(declarations),
            "declarations": declarations,
        })
    return id_conflicts, attribute_conflicts, syntax_conflicts, malformed_header_conflicts


def duplicate_resource_ids(scene_text: str) -> list[dict[str, object]]:
    return resource_table_conflicts(scene_text)[0]


def self_test() -> None:
    normal = '''
[gd_scene load_steps=3 format=3]
[ext_resource type="ArrayMesh" path="res://assets/body.mesh" id="Mesh_body"]
[sub_resource type="Skin" id="Skin_body"]
[node name="Main" type="Node3D"]
'''
    ids, attrs, syntax, malformed = resource_table_conflicts(normal)
    assert ids == [] and attrs == [] and syntax == [] and malformed == []

    duplicate_ext = normal.replace(
        '[sub_resource type="Skin" id="Skin_body"]',
        '[ext_resource type="Skin" path="res://assets/body.skin" id="Mesh_body"]\n[sub_resource type="Skin" id="Skin_body"]',
    )
    ids, attrs, syntax, malformed = resource_table_conflicts(duplicate_ext)
    assert len(ids) == 1 and attrs == [] and syntax == [] and malformed == []
    assert ids[0]["kind"] == "ExtResource"
    assert ids[0]["id"] == "Mesh_body"
    assert ids[0]["declaration_count"] == 2
    parsed = skin.parse_resource_table(duplicate_ext)
    assert parsed[("ExtResource", "Mesh_body")]["type"] == "Skin", (
        "regression precondition: legacy dict parsing silently overwrites duplicate resource ids"
    )

    duplicate_sub = normal + '\n[sub_resource type="ArrayMesh" id="Skin_body"]\n'
    ids, attrs, syntax, malformed = resource_table_conflicts(duplicate_sub)
    assert len(ids) == 1 and attrs == [] and syntax == [] and malformed == []
    assert ids[0]["kind"] == "SubResource"

    cross_kind_same_id = normal + '\n[sub_resource type="ArrayMesh" id="Mesh_body"]\n'
    ids, attrs, syntax, malformed = resource_table_conflicts(cross_kind_same_id)
    assert ids == [] and attrs == [] and syntax == [] and malformed == []

    duplicate_id_attribute = normal.replace(
        '[ext_resource type="ArrayMesh" path="res://assets/body.mesh" id="Mesh_body"]',
        '[ext_resource type="ArrayMesh" path="res://assets/body.mesh" id="Mesh_old" id="Mesh_body"]',
    )
    ids, attrs, syntax, malformed = resource_table_conflicts(duplicate_id_attribute)
    assert ids == [] and syntax == [] and malformed == []
    assert len(attrs) == 1 and attrs[0]["duplicate_attributes"] == ["id"]
    assert attrs[0]["attribute_occurrences"]["id"] == 2

    duplicate_type_attribute = normal.replace(
        '[ext_resource type="ArrayMesh" path="res://assets/body.mesh" id="Mesh_body"]',
        '[ext_resource type="Skin" type="ArrayMesh" path="res://assets/body.mesh" id="Mesh_body"]',
    )
    ids, attrs, syntax, malformed = resource_table_conflicts(duplicate_type_attribute)
    assert ids == [] and syntax == [] and malformed == []
    assert len(attrs) == 1 and attrs[0]["duplicate_attributes"] == ["type"]

    duplicate_path_attribute = normal.replace(
        'path="res://assets/body.mesh"',
        'path="res://assets/forged.mesh" path="res://assets/body.mesh"',
    )
    ids, attrs, syntax, malformed = resource_table_conflicts(duplicate_path_attribute)
    assert ids == [] and syntax == [] and malformed == []
    assert len(attrs) == 1 and attrs[0]["duplicate_attributes"] == ["path"]

    spaced_duplicate = normal.replace(
        'id="Mesh_body"',
        'id = "Mesh_old" id="Mesh_body"',
        1,
    )
    legacy_pairs = re.findall(r'\b([A-Za-z_][A-Za-z0-9_]*)="([^"]*)"', spaced_duplicate.splitlines()[2])
    assert [value for name, value in legacy_pairs if name == "id"] == ["Mesh_body"]
    ids, attrs, syntax, malformed = resource_table_conflicts(spaced_duplicate)
    assert ids == [] and syntax == [] and malformed == []
    assert len(attrs) == 1
    assert attrs[0]["duplicate_attributes"] == ["id"]
    assert attrs[0]["attribute_occurrences"]["id"] == 2

    spaced_normal = normal.replace('type="ArrayMesh"', 'type = "ArrayMesh"', 1)
    ids, attrs, syntax, malformed = resource_table_conflicts(spaced_normal)
    assert ids == [] and attrs == [] and syntax == [] and malformed == []

    partial = normal.replace(
        'path="res://assets/body.mesh"',
        'path="res://assets/body.mesh" forged_token',
    )
    ids, attrs, syntax, malformed = resource_table_conflicts(partial)
    assert ids == [] and attrs == [] and malformed == []
    assert len(syntax) == 1
    assert syntax[0]["unparsed_fragment"] == "forged_token"

    # v3 blind spot: an outer resource header missing its closing bracket never
    # matched EXT_RE/SUB_RE, so it disappeared from the evidence table entirely.
    missing_close = normal.replace(
        '[ext_resource type="ArrayMesh" path="res://assets/body.mesh" id="Mesh_body"]',
        '[ext_resource type="ArrayMesh" path="res://assets/body.mesh" id="Mesh_body"',
    )
    legacy_outer_matches = [line for line in missing_close.splitlines() if EXT_RE.match(line) or SUB_RE.match(line)]
    assert len(legacy_outer_matches) == 1, (
        "regression precondition: v3 silently ignores the malformed ExtResource header"
    )
    ids, attrs, syntax, malformed = resource_table_conflicts(missing_close)
    assert ids == [] and attrs == [] and syntax == []
    assert len(malformed) == 1
    assert malformed[0]["kind"] == "ExtResource"
    assert malformed[0]["reason"] == "resource_header_did_not_match_complete_bracketed_grammar"

    malformed_sub = normal.replace(
        '[sub_resource type="Skin" id="Skin_body"]',
        '[sub_resource type="Skin" id="Skin_body" trailing_junk',
    )
    ids, attrs, syntax, malformed = resource_table_conflicts(malformed_sub)
    assert ids == [] and attrs == [] and syntax == []
    assert len(malformed) == 1 and malformed[0]["kind"] == "SubResource"


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        self_test()
        print("CIV1_RESOURCE_TABLE_UNIQUENESS_SELF_TEST_OK")
        return 0
    if len(sys.argv) != 3:
        print("usage: civ1_resource_table_uniqueness.py MAIN_TSCN OUT", file=sys.stderr)
        return 2

    main_tscn = Path(sys.argv[1]).resolve()
    out_path = Path(sys.argv[2])
    project_root = main_tscn.parent.parent
    scenes = skin.reachable_scenes(main_tscn, project_root)
    id_conflicts: list[dict[str, object]] = []
    attribute_conflicts: list[dict[str, object]] = []
    syntax_conflicts: list[dict[str, object]] = []
    malformed_header_conflicts: list[dict[str, object]] = []
    for scene_path in scenes:
        rel = scene_path.relative_to(project_root).as_posix()
        text = scene_path.read_text(encoding="utf-8")
        scene_ids, scene_attrs, scene_syntax, scene_malformed = resource_table_conflicts(text)
        for conflict in scene_ids:
            id_conflicts.append({"scene": rel, **conflict})
        for conflict in scene_attrs:
            attribute_conflicts.append({"scene": rel, **conflict})
        for conflict in scene_syntax:
            syntax_conflicts.append({"scene": rel, **conflict})
        for conflict in scene_malformed:
            malformed_header_conflicts.append({"scene": rel, **conflict})

    identity_unambiguous = (
        not id_conflicts
        and not attribute_conflicts
        and not syntax_conflicts
        and not malformed_header_conflicts
    )
    result = {
        "schema": SCHEMA,
        "evidence_mode": "reachable_tscn_plus_unique_resource_id_namespace_plus_complete_outer_header_grammar_plus_whitespace_tolerant_fully_parsed_unambiguous_resource_header_attributes",
        "reachable_scene_count": len(scenes),
        "duplicate_resource_id_conflicts": id_conflicts,
        "duplicate_resource_attribute_conflicts": attribute_conflicts,
        "unparsed_resource_header_fragments": syntax_conflicts,
        "malformed_resource_header_conflicts": malformed_header_conflicts,
        "resource_header_attributes_unambiguous": not attribute_conflicts,
        "resource_header_syntax_fully_parsed": not syntax_conflicts,
        "resource_outer_header_syntax_valid": not malformed_header_conflicts,
        "resource_table_identity_unambiguous": identity_unambiguous,
        "duplicate_resource_id_evidence_accepted": False,
        "duplicate_resource_attribute_evidence_accepted": False,
        "partially_parsed_resource_header_evidence_accepted": False,
        "spaced_duplicate_attribute_evidence_accepted": False,
        "malformed_outer_resource_header_evidence_accepted": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "contact_verified": False,
        "foot_slide_verified": False,
        "next_action": (
            "remove duplicate ids/attributes, unparsed fragments and malformed outer resource headers before authored Character integrity can be trusted"
            if not identity_unambiguous
            else "retain complete, fully parsed unique resource-header gates before authored Character loaded-scene approval"
        ),
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
