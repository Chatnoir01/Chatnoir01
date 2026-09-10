#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from collections import Counter
from pathlib import Path

import civ1_authored_skin_integrity as skin

SCHEMA = "grand-bruxelles-civ1-resource-table-uniqueness-v5"
EXT_RE = re.compile(r'^\s*\[ext_resource\s+(.+?)\]\s*$')
SUB_RE = re.compile(r'^\s*\[sub_resource\s+(.+?)\]\s*$')
RESOURCE_PREFIX_RE = re.compile(r'^\s*\[(ext_resource|sub_resource)\b')
ATTR_RE = re.compile(r'\b([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"((?:\\.|[^"\\])*)"')


def _decode_quoted(raw: str) -> str | None:
    try:
        value = json.loads('"' + raw + '"')
    except (json.JSONDecodeError, UnicodeDecodeError):
        return None
    return value if isinstance(value, str) else None


def parse_header_attributes(header: str) -> tuple[list[tuple[str, str]], str]:
    pairs: list[tuple[str, str]] = []
    cursor = 0
    residue: list[str] = []
    for match in ATTR_RE.finditer(header):
        between = header[cursor:match.start()]
        if between.strip():
            residue.append(between.strip())
        decoded = _decode_quoted(match.group(2))
        if decoded is None:
            residue.append(match.group(0))
        else:
            pairs.append((match.group(1), decoded))
        cursor = match.end()
    tail = header[cursor:]
    if tail.strip():
        residue.append(tail.strip())
    return pairs, " ".join(residue)


def resource_table_conflicts(scene_text: str) -> tuple[list[dict[str, object]], list[dict[str, object]], list[dict[str, object]], list[dict[str, object]]]:
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
            syntax_conflicts.append({"kind": kind, "line": line_number, "unparsed_fragment": residue, "raw_header": line.strip()})

        attr_counts = Counter(name for name, _ in attr_pairs)
        duplicate_attributes = sorted(name for name, count in attr_counts.items() if count > 1)
        if duplicate_attributes:
            attribute_conflicts.append({
                "kind": kind,
                "line": line_number,
                "duplicate_attributes": duplicate_attributes,
                "attribute_occurrences": {name: attr_counts[name] for name in duplicate_attributes},
                "raw_header": line.strip(),
            })

        attrs = dict(attr_pairs)
        rid = attrs.get("id")
        if not rid:
            continue
        seen.setdefault((kind, rid), []).append({"line": str(line_number), "type": attrs.get("type", ""), "path": attrs.get("path", "")})

    id_conflicts: list[dict[str, object]] = []
    for (kind, rid), declarations in sorted(seen.items()):
        if len(declarations) > 1:
            id_conflicts.append({"kind": kind, "id": rid, "declaration_count": len(declarations), "declarations": declarations})
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

    duplicate_ext = normal.replace('[sub_resource type="Skin" id="Skin_body"]', '[ext_resource type="Skin" path="res://assets/body.skin" id="Mesh_body"]\n[sub_resource type="Skin" id="Skin_body"]')
    ids, attrs, syntax, malformed = resource_table_conflicts(duplicate_ext)
    assert len(ids) == 1 and attrs == [] and syntax == [] and malformed == []
    parsed = skin.parse_resource_table(duplicate_ext)
    assert parsed[("ExtResource", "Mesh_body")]["type"] == "Skin"

    duplicate_sub = normal + '\n[sub_resource type="ArrayMesh" id="Skin_body"]\n'
    ids, attrs, syntax, malformed = resource_table_conflicts(duplicate_sub)
    assert len(ids) == 1 and attrs == [] and syntax == [] and malformed == []

    cross_kind_same_id = normal + '\n[sub_resource type="ArrayMesh" id="Mesh_body"]\n'
    ids, attrs, syntax, malformed = resource_table_conflicts(cross_kind_same_id)
    assert ids == [] and attrs == [] and syntax == [] and malformed == []

    duplicate_id_attribute = normal.replace('id="Mesh_body"', 'id="Mesh_old" id="Mesh_body"', 1)
    ids, attrs, syntax, malformed = resource_table_conflicts(duplicate_id_attribute)
    assert ids == [] and syntax == [] and malformed == [] and len(attrs) == 1

    spaced_duplicate = normal.replace('id="Mesh_body"', 'id = "Mesh_old" id="Mesh_body"', 1)
    ids, attrs, syntax, malformed = resource_table_conflicts(spaced_duplicate)
    assert ids == [] and syntax == [] and malformed == [] and len(attrs) == 1

    partial = normal.replace('path="res://assets/body.mesh"', 'path="res://assets/body.mesh" forged_token')
    ids, attrs, syntax, malformed = resource_table_conflicts(partial)
    assert ids == [] and attrs == [] and malformed == [] and len(syntax) == 1

    missing_close = normal.replace('[ext_resource type="ArrayMesh" path="res://assets/body.mesh" id="Mesh_body"]', '[ext_resource type="ArrayMesh" path="res://assets/body.mesh" id="Mesh_body"')
    ids, attrs, syntax, malformed = resource_table_conflicts(missing_close)
    assert ids == [] and attrs == [] and syntax == [] and len(malformed) == 1

    # v4 blind spot: raw quoted values were compared without decoding escapes.
    escaped_alias = normal + '\n[ext_resource type="Skin" path="res://assets/body.skin" id="Mesh\\u005fbody"]\n'
    legacy_raw_ids = [m.group(2) for line in escaped_alias.splitlines() for m in [EXT_RE.match(line)] if m for name, value in ATTR_RE.findall(m.group(1)) if name == "id"]
    assert "Mesh_body" in legacy_raw_ids and "Mesh\\u005fbody" in legacy_raw_ids
    assert len(set(legacy_raw_ids)) == 2, "regression precondition: v4 sees escaped and decoded ids as distinct"
    ids, attrs, syntax, malformed = resource_table_conflicts(escaped_alias)
    assert attrs == [] and syntax == [] and malformed == []
    assert len(ids) == 1 and ids[0]["id"] == "Mesh_body" and ids[0]["declaration_count"] == 2

    invalid_escape = normal.replace('id="Mesh_body"', 'id="Mesh\\qbody"', 1)
    ids, attrs, syntax, malformed = resource_table_conflicts(invalid_escape)
    assert ids == [] and attrs == [] and malformed == [] and len(syntax) == 1


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        self_test()
        print("CIV1_RESOURCE_TABLE_UNIQUENESS_SELF_TEST_OK")
        return 0
    if len(sys.argv) != 3:
        print("usage: civ1_resource_table_uniQUENESS.py MAIN_TSCN OUT", file=sys.stderr)
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
        id_conflicts.extend({"scene": rel, **c} for c in scene_ids)
        attribute_conflicts.extend({"scene": rel, **c} for c in scene_attrs)
        syntax_conflicts.extend({"scene": rel, **c} for c in scene_syntax)
        malformed_header_conflicts.extend({"scene": rel, **c} for c in scene_malformed)

    identity_unambiguous = not id_conflicts and not attribute_conflicts and not syntax_conflicts and not malformed_header_conflicts
    result = {
        "schema": SCHEMA,
        "evidence_mode": "reachable_tscn_plus_unique_decoded_resource_id_namespace_plus_complete_outer_header_grammar_plus_whitespace_tolerant_fully_parsed_unambiguous_decoded_resource_header_attributes",
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
        "escaped_resource_identity_evidence_accepted": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "contact_verified": False,
        "foot_slide_verified": False,
        "next_action": "retain decoded, fully parsed unique resource-header identity gates before Godot loaded-scene authored-character approval" if identity_unambiguous else "remove duplicate decoded ids/attributes, invalid escapes, unparsed fragments and malformed resource headers before authored Character integrity can be trusted",
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
