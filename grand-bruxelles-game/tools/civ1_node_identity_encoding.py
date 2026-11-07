#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import civ1_authored_skin_integrity as skin
import civ1_node_table_uniqueness as node_table

SCHEMA = "grand-bruxelles-civ1-node-identity-encoding-v2"
NODE_RE = re.compile(r'^\s*\[node\s+(.+?)\]\s*$')
NAME_RE = re.compile(r'[A-Za-z_][A-Za-z0-9_]*')
IDENTITY_ATTRIBUTES = {"name", "parent", "type"}
OPENERS = {'(': ')', '[': ']'}
CLOSERS = {')': '(', ']': '['}


def raw_header_values(header: str) -> list[tuple[str, str]]:
    values: list[tuple[str, str]] = []
    i = 0
    n = len(header)
    while i < n:
        while i < n and header[i].isspace():
            i += 1
        if i >= n:
            break
        name_match = NAME_RE.match(header, i)
        if not name_match:
            break
        name = name_match.group(0)
        i = name_match.end()
        while i < n and header[i].isspace():
            i += 1
        if i >= n or header[i] != '=':
            break
        i += 1
        while i < n and header[i].isspace():
            i += 1
        start = i
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
        raw = header[start:i].strip()
        if raw:
            values.append((name, raw))
    return values


def _decode_quoted(raw: str) -> str | None:
    if not (len(raw) >= 2 and raw.startswith('"') and raw.endswith('"')):
        return None
    try:
        return node_table.decode_quoted_value(raw)
    except (json.JSONDecodeError, ValueError):
        return None


def identity_encoding_conflicts(scene_text: str) -> list[dict[str, object]]:
    conflicts: list[dict[str, object]] = []
    for line_number, line in enumerate(scene_text.splitlines(), start=1):
        match = NODE_RE.match(line)
        if not match:
            continue
        for name, raw in raw_header_values(match.group(1)):
            if name not in IDENTITY_ATTRIBUTES:
                continue
            decoded = _decode_quoted(raw)
            if decoded is None:
                conflicts.append({
                    "line": line_number,
                    "attribute": name,
                    "raw_value": raw,
                    "reason": "node_identity_attribute_must_be_valid_quoted_string",
                    "raw_header": line.strip(),
                })
                continue
            if name == "name" and "/" in decoded:
                conflicts.append({
                    "line": line_number,
                    "attribute": name,
                    "raw_value": raw,
                    "decoded_value": decoded,
                    "reason": "node_name_must_be_single_nodepath_segment",
                    "raw_header": line.strip(),
                })
    return conflicts


def _legacy_v1_accepts_path_injected_name(header: str) -> bool:
    # v1 only required quotes; it did not constrain the decoded node name to
    # a single NodePath segment, so a slash could forge apparent hierarchy.
    pairs = dict(raw_header_values(header))
    raw = pairs.get("name", "")
    return len(raw) >= 2 and raw.startswith('"') and raw.endswith('"')


def self_test() -> None:
    normal = '''
[gd_scene load_steps=1 format=3]
[node name="Main" type="Node3D"]
[node name="NpcAgent" type="CharacterBody3D" parent="."]
[node name="CharacterMount" type="Node3D" parent="NpcAgent"]
[node name="Instance" parent="." instance=ExtResource("1_scene") groups=["ambient_pedestrian"]]
'''
    assert identity_encoding_conflicts(normal) == []

    forged_header = 'name=NpcAgent type=CharacterBody3D parent="."'
    forged_name_type = normal.replace('name="NpcAgent" type="CharacterBody3D"', 'name=NpcAgent type=CharacterBody3D')
    conflicts = identity_encoding_conflicts(forged_name_type)
    assert [(c["attribute"], c["raw_value"]) for c in conflicts] == [("name", "NpcAgent"), ("type", "CharacterBody3D")]

    forged_parent = normal.replace('parent="NpcAgent"', 'parent=NpcAgent')
    conflicts = identity_encoding_conflicts(forged_parent)
    assert len(conflicts) == 1 and conflicts[0]["attribute"] == "parent" and conflicts[0]["raw_value"] == "NpcAgent"

    # v1 blind spot: a quoted name containing '/' was accepted and the legacy
    # evidence parser would concatenate it into a deeper apparent NodePath.
    path_injected = '[node name="CharacterMount/Skeleton3D" type="Skeleton3D" parent="NpcAgent"]'
    assert _legacy_v1_accepts_path_injected_name('name="CharacterMount/Skeleton3D" type="Skeleton3D" parent="NpcAgent"')
    legacy_block = skin.parse_node_blocks(path_injected)[0]
    assert skin.node_path(legacy_block["attrs"]) == "NpcAgent/CharacterMount/Skeleton3D"
    conflicts = identity_encoding_conflicts(path_injected)
    assert len(conflicts) == 1 and conflicts[0]["attribute"] == "name" and conflicts[0]["decoded_value"] == "CharacterMount/Skeleton3D"

    escaped_path_injected = '[node name="CharacterMount\\u002fSkeleton3D" type="Skeleton3D" parent="NpcAgent"]'
    conflicts = identity_encoding_conflicts(escaped_path_injected)
    assert len(conflicts) == 1 and conflicts[0]["decoded_value"] == "CharacterMount/Skeleton3D", "escaped slash must not bypass single-segment identity"

    # Structured non-identity attributes remain legal and must not be over-rejected.
    assert identity_encoding_conflicts('[node name="Instance" parent="." instance=ExtResource("1_scene") groups=["ambient_pedestrian"]]\n') == []


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        self_test()
        print("CIV1_NODE_IDENTITY_ENCODING_SELF_TEST_OK")
        return 0
    if len(sys.argv) != 3:
        print("usage: civ1_node_identity_encoding.py MAIN_TSCN OUT", file=sys.stderr)
        return 2
    main_tscn = Path(sys.argv[1]).resolve()
    out_path = Path(sys.argv[2])
    project_root = main_tscn.parent.parent
    scenes = skin.reachable_scenes(main_tscn, project_root)
    conflicts: list[dict[str, object]] = []
    for scene_path in scenes:
        rel = scene_path.relative_to(project_root).as_posix()
        for item in identity_encoding_conflicts(scene_path.read_text(encoding="utf-8")):
            conflicts.append({"scene": rel, **item})
    result = {
        "schema": SCHEMA,
        "evidence_mode": "reachable_tscn_plus_valid_quoted_identity_plus_single_segment_node_name",
        "reachable_scene_count": len(scenes),
        "node_identity_encoding_conflicts": conflicts,
        "node_identity_attributes_canonically_quoted": not any(c["reason"].startswith("node_identity_attribute") for c in conflicts),
        "node_names_single_segment": not any(c["reason"] == "node_name_must_be_single_nodepath_segment" for c in conflicts),
        "unquoted_node_identity_evidence_accepted": False,
        "path_injected_node_name_evidence_accepted": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "contact_verified": False,
        "foot_slide_verified": False,
        "next_action": "repair node identity encoding/path-segment conflicts before Character hierarchy evidence can be trusted" if conflicts else "retain canonical identity and single-segment node-name gate before authored Character loaded-scene approval",
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
