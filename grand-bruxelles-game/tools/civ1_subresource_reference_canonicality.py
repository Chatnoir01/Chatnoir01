#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path

import civ1_authored_skin_integrity as skin
import civ1_subresource_reference_order as order

SCHEMA = "grand-bruxelles-civ1-subresource-reference-canonicality-v1"
TOKEN = "SubResource"


def _scan_reference(value: str, start: int) -> tuple[int, str | None, str | None]:
    """Return (end, decoded_id, reason). start points at TOKEN."""
    cursor = start + len(TOKEN)
    if cursor >= len(value) or value[cursor] != "(":
        return cursor, None, "subresource_reference_whitespace_or_missing_open_paren"
    cursor += 1
    if cursor >= len(value) or value[cursor] != '"':
        return cursor, None, "subresource_reference_whitespace_or_missing_quote"
    quote_start = cursor
    cursor += 1
    escaped = False
    while cursor < len(value):
        ch = value[cursor]
        if ch == "\\":
            escaped = True
            cursor += 2
            continue
        if ch == '"':
            break
        cursor += 1
    if cursor >= len(value) or value[cursor] != '"':
        return cursor, None, "unterminated_subresource_reference_id"
    raw_literal = value[quote_start : cursor + 1]
    try:
        decoded = json.loads(raw_literal)
    except (json.JSONDecodeError, UnicodeDecodeError):
        return cursor + 1, None, "invalid_subresource_reference_escape"
    if not isinstance(decoded, str) or not decoded:
        return cursor + 1, None, "empty_or_nonstring_subresource_reference_id"
    cursor += 1
    if cursor >= len(value) or value[cursor] != ")":
        return cursor, decoded, "subresource_reference_whitespace_or_missing_close_paren"
    cursor += 1
    if escaped:
        return cursor, decoded, "escaped_subresource_reference_id_alias"
    if raw_literal != '"' + decoded + '"':
        return cursor, decoded, "noncanonical_subresource_reference_id_spelling"
    return cursor, decoded, None


def subresource_reference_canonicality_conflicts(scene_text: str) -> list[dict[str, object]]:
    conflicts: list[dict[str, object]] = []
    current_section = ""
    for line_number, line in enumerate(scene_text.splitlines(), start=1):
        stripped = line.lstrip()
        if stripped.startswith("["):
            current_section = stripped.split("]", 1)[0] + "]" if "]" in stripped else ""
            continue
        if "=" not in line:
            continue
        _, value = line.split("=", 1)
        cursor = 0
        in_string = False
        escaped_in_string = False
        while cursor < len(value):
            ch = value[cursor]
            if in_string:
                if escaped_in_string:
                    escaped_in_string = False
                elif ch == "\\":
                    escaped_in_string = True
                elif ch == '"':
                    in_string = False
                cursor += 1
                continue
            if ch == '"':
                in_string = True
                cursor += 1
                continue
            if value.startswith(TOKEN, cursor):
                before_ok = cursor == 0 or not (value[cursor - 1].isalnum() or value[cursor - 1] == "_")
                after_index = cursor + len(TOKEN)
                after_ok = after_index >= len(value) or not (value[after_index].isalnum() or value[after_index] == "_")
                if before_ok and after_ok:
                    end, decoded, reason = _scan_reference(value, cursor)
                    if reason:
                        conflicts.append({
                            "line": line_number,
                            "section": current_section,
                            "referenced_subresource_id": decoded,
                            "reason": reason,
                            "lexeme": value[cursor:max(end, cursor + len(TOKEN))].strip(),
                        })
                    cursor = max(end, cursor + len(TOKEN))
                    continue
            cursor += 1
    return conflicts


def self_test() -> None:
    canonical = '''
[gd_scene format=3]
[sub_resource type="StandardMaterial3D" id="Mat_body"]
[sub_resource type="ArrayMesh" id="Mesh_body"]
surface_0/material = SubResource("Mat_body")
[node name="Main" type="Node3D"]
'''
    assert subresource_reference_canonicality_conflicts(canonical) == []

    escaped_alias = canonical.replace('SubResource("Mat_body")', 'SubResource("Mat\\u005fbody")')
    # RED witness: the previous order gate decodes the alias and reports it valid.
    assert order.subresource_reference_order_conflicts(escaped_alias) == []
    conflicts = subresource_reference_canonicality_conflicts(escaped_alias)
    assert len(conflicts) == 1
    assert conflicts[0]["reason"] == "escaped_subresource_reference_id_alias"
    assert conflicts[0]["referenced_subresource_id"] == "Mat_body"

    whitespace_alias = canonical.replace('SubResource("Mat_body")', 'SubResource( "Mat_body" )')
    # RED witness: the previous regex does not see this invocation, so it also returns valid.
    assert order.subresource_reference_order_conflicts(whitespace_alias) == []
    conflicts = subresource_reference_canonicality_conflicts(whitespace_alias)
    assert len(conflicts) == 1
    assert conflicts[0]["reason"] == "subresource_reference_whitespace_or_missing_quote"

    string_literal = canonical + '\nmetadata/note = "SubResource(\\\"Mat_body\\\") is documentation"\n'
    assert subresource_reference_canonicality_conflicts(string_literal) == []

    nested = canonical.replace(
        'surface_0/material = SubResource("Mat_body")',
        'payload = [SubResource("Mat_body"), {"mesh": SubResource("Mat_body")} ]',
    )
    assert subresource_reference_canonicality_conflicts(nested) == []


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        self_test()
        print("CIV1_SUBRESOURCE_REFERENCE_CANONICALITY_SELF_TEST_OK")
        return 0
    if len(sys.argv) != 3:
        print("usage: civ1_subresource_reference_canonicality.py MAIN_TSCN OUT", file=sys.stderr)
        return 2

    main_tscn = Path(sys.argv[1]).resolve()
    out_path = Path(sys.argv[2])
    project_root = main_tscn.parent.parent
    scenes = skin.reachable_scenes(main_tscn, project_root)
    conflicts: list[dict[str, object]] = []
    for scene_path in scenes:
        rel = scene_path.relative_to(project_root).as_posix()
        for conflict in subresource_reference_canonicality_conflicts(scene_path.read_text(encoding="utf-8")):
            conflicts.append({"scene": rel, **conflict})

    result = {
        "schema": SCHEMA,
        "evidence_mode": "reachable_tscn_plus_exact_SubResource_reference_lexemes",
        "reachable_scene_count": len(scenes),
        "subresource_reference_canonicality_conflicts": conflicts,
        "subresource_reference_lexemes_canonical": not conflicts,
        "escaped_subresource_reference_alias_evidence_accepted": False,
        "whitespace_subresource_reference_alias_evidence_accepted": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "contact_verified": False,
        "foot_slide_verified": False,
        "next_action": (
            "retain exact SubResource(\"id\") spelling before authored Character loaded-scene approval"
            if not conflicts
            else "rewrite every internal SubResource reference to exact canonical SubResource(\"id\") spelling"
        ),
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0 if not conflicts else 1


if __name__ == "__main__":
    raise SystemExit(main())
