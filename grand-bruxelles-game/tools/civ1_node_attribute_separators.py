#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import civ1_authored_skin_integrity as skin

SCHEMA = "grand-bruxelles-civ1-node-attribute-separators-v1"
NODE_RE = re.compile(r'^\s*\[node\s+(.+?)\]\s*$')
NODE_PREFIX_RE = re.compile(r'^\s*\[node\b')
NAME_RE = re.compile(r'[A-Za-z_][A-Za-z0-9_]*')
OPENERS = {'(': ')', '[': ']'}
CLOSERS = {')': '(', ']': '['}


def separator_conflicts(scene_text: str) -> list[dict[str, object]]:
    conflicts: list[dict[str, object]] = []
    for line_number, line in enumerate(scene_text.splitlines(), start=1):
        match = NODE_RE.match(line)
        if not match:
            continue
        header = match.group(1)
        i = 0
        n = len(header)
        first = True
        while i < n:
            ws_start = i
            while i < n and header[i].isspace():
                i += 1
            had_separator = i > ws_start
            if i >= n:
                break
            if not first and not had_separator:
                conflicts.append({
                    "line": line_number,
                    "offset": i,
                    "reason": "node_header_attributes_must_be_whitespace_separated",
                    "raw_header": line.strip(),
                })
                break
            first = False
            name_match = NAME_RE.match(header, i)
            if not name_match:
                break
            i = name_match.end()
            while i < n and header[i].isspace():
                i += 1
            if i >= n or header[i] != '=':
                break
            i += 1
            while i < n and header[i].isspace():
                i += 1
            if i >= n:
                break
            if header[i] == '"':
                i += 1
                escaped = False
                while i < n:
                    ch = header[i]
                    if escaped:
                        escaped = False
                    elif ch == '\\':
                        escaped = True
                    elif ch == '"':
                        i += 1
                        break
                    i += 1
                else:
                    break
            else:
                stack: list[str] = []
                in_string = False
                escaped = False
                saw_structure = False
                while i < n:
                    ch = header[i]
                    if in_string:
                        if escaped:
                            escaped = False
                        elif ch == '\\':
                            escaped = True
                        elif ch == '"':
                            in_string = False
                    else:
                        if ch == '"':
                            in_string = True
                        elif ch in OPENERS:
                            stack.append(ch)
                            saw_structure = True
                        elif ch in CLOSERS:
                            if not stack or stack[-1] != CLOSERS[ch]:
                                break
                            stack.pop()
                            if saw_structure and not stack:
                                i += 1
                                break
                        elif ch.isspace() and not stack:
                            break
                    i += 1
                if stack or in_string:
                    break
    return conflicts


def _v4_accepts_missing_separator(header: str) -> bool:
    from civ1_node_table_uniqueness import parse_header_attributes
    pairs, residue = parse_header_attributes(header)
    return len(pairs) >= 2 and residue == ""


def self_test() -> None:
    normal = '''
[gd_scene load_steps=1 format=3]
[node name="Main" type="Node3D"]
[node name="NpcAgent" type="CharacterBody3D" parent="."]
[node name="Instance" parent="." instance=ExtResource("1_scene") groups=["ambient_pedestrian"]]
'''
    assert separator_conflicts(normal) == []

    quoted = 'name="NpcAgent"type="CharacterBody3D" parent="."'
    assert _v4_accepts_missing_separator(quoted), "regression precondition: node-table v4 accepts concatenated quoted attributes"
    forged_quoted = normal.replace('name="NpcAgent" type="CharacterBody3D"', 'name="NpcAgent"type="CharacterBody3D"')
    conflicts = separator_conflicts(forged_quoted)
    assert len(conflicts) == 1 and conflicts[0]["reason"] == "node_header_attributes_must_be_whitespace_separated"

    structured = 'name="Instance" parent="." instance=ExtResource("1_scene")groups=["ambient_pedestrian"]'
    assert _v4_accepts_missing_separator(structured), "regression precondition: node-table v4 accepts concatenated structured attributes"
    forged_structured = normal.replace('instance=ExtResource("1_scene") groups=', 'instance=ExtResource("1_scene")groups=')
    conflicts = separator_conflicts(forged_structured)
    assert len(conflicts) == 1 and conflicts[0]["reason"] == "node_header_attributes_must_be_whitespace_separated"


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        self_test()
        print("CIV1_NODE_ATTRIBUTE_SEPARATORS_SELF_TEST_OK")
        return 0
    if len(sys.argv) != 3:
        print("usage: civ1_node_attribute_separators.py MAIN_TSCN OUT", file=sys.stderr)
        return 2
    main_tscn = Path(sys.argv[1]).resolve()
    out_path = Path(sys.argv[2])
    project_root = main_tscn.parent.parent
    scenes = skin.reachable_scenes(main_tscn, project_root)
    conflicts: list[dict[str, object]] = []
    for scene_path in scenes:
        rel = scene_path.relative_to(project_root).as_posix()
        for item in separator_conflicts(scene_path.read_text(encoding="utf-8")):
            conflicts.append({"scene": rel, **item})
    result = {
        "schema": SCHEMA,
        "evidence_mode": "reachable_tscn_plus_explicit_whitespace_separation_between_node_header_attributes",
        "reachable_scene_count": len(scenes),
        "missing_node_attribute_separator_conflicts": conflicts,
        "node_header_attribute_separators_valid": not conflicts,
        "concatenated_node_attribute_evidence_accepted": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "contact_verified": False,
        "foot_slide_verified": False,
        "next_action": "insert whitespace between every adjacent node-header attribute before Character hierarchy evidence can be trusted" if conflicts else "retain explicit node-header attribute separator gate before authored Character loaded-scene approval",
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
