#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from collections import Counter
from pathlib import Path

import civ1_authored_skin_integrity as skin

SCHEMA = "grand-bruxelles-civ1-node-table-uniqueness-v4"
NODE_RE = re.compile(r'^\s*\[node\s+(.+?)\]\s*$')
NODE_PREFIX_RE = re.compile(r'^\s*\[node\b')
NAME_RE = re.compile(r'[A-Za-z_][A-Za-z0-9_]*')
OPENERS = {'(': ')', '[': ']'}
CLOSERS = {')': '(', ']': '['}


def decode_quoted_value(value: str) -> str:
    decoded = json.loads(value)
    if not isinstance(decoded, str):
        raise ValueError("quoted node-header value did not decode to a string")
    return decoded


def parse_header_attributes(header: str) -> tuple[list[tuple[str, str]], str]:
    pairs: list[tuple[str, str]] = []
    residue: list[str] = []
    i = 0
    n = len(header)
    while i < n:
        while i < n and header[i].isspace():
            i += 1
        if i >= n:
            break
        name_match = NAME_RE.match(header, i)
        if not name_match:
            residue.append(header[i:].strip())
            break
        name = name_match.group(0)
        i = name_match.end()
        while i < n and header[i].isspace():
            i += 1
        if i >= n or header[i] != '=':
            residue.append(header[name_match.start():].strip())
            break
        i += 1
        while i < n and header[i].isspace():
            i += 1
        value_start = i
        if i >= n:
            residue.append(f"{name}=")
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
                residue.append(header[name_match.start():].strip())
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
                            residue.append(header[name_match.start():i + 1].strip())
                            return pairs, " ".join(r for r in residue if r)
                        stack.pop()
                        if saw_structure and not stack:
                            i += 1
                            break
                    elif ch.isspace() and not stack:
                        break
                i += 1
            if stack or in_string:
                residue.append(header[name_match.start():].strip())
                break
        value = header[value_start:i].strip()
        if not value:
            residue.append(f"{name}=")
            break
        if value.startswith('"') and value.endswith('"'):
            try:
                parsed_value = decode_quoted_value(value)
            except (json.JSONDecodeError, ValueError):
                residue.append(header[name_match.start():i].strip())
                break
        else:
            parsed_value = value
        pairs.append((name, parsed_value))
    return pairs, " ".join(r for r in residue if r)


def declared_node_path(attrs: dict[str, str]) -> str | None:
    name = attrs.get("name")
    if not name:
        return None
    parent = attrs.get("parent", ".")
    return name if parent in ("", ".") else f"{parent}/{name}".strip("/")


def node_table_conflicts(scene_text: str) -> tuple[list[dict[str, object]], list[dict[str, object]], list[dict[str, object]], list[dict[str, object]]]:
    seen_paths: dict[str, list[dict[str, object]]] = {}
    attribute_conflicts: list[dict[str, object]] = []
    syntax_conflicts: list[dict[str, object]] = []
    malformed_header_conflicts: list[dict[str, object]] = []
    for line_number, line in enumerate(scene_text.splitlines(), start=1):
        match = NODE_RE.match(line)
        if not match:
            if NODE_PREFIX_RE.match(line):
                malformed_header_conflicts.append({"line": line_number, "raw_header": line.strip(), "reason": "node_header_did_not_match_complete_bracketed_grammar"})
            continue
        attr_pairs, residue = parse_header_attributes(match.group(1))
        if residue:
            syntax_conflicts.append({"line": line_number, "unparsed_fragment": residue, "raw_header": line.strip()})
        counts = Counter(name for name, _ in attr_pairs)
        duplicate_attributes = sorted(name for name, count in counts.items() if count > 1)
        if duplicate_attributes:
            attribute_conflicts.append({"line": line_number, "duplicate_attributes": duplicate_attributes, "attribute_occurrences": {name: counts[name] for name in duplicate_attributes}, "raw_header": line.strip()})
        attrs = dict(attr_pairs)
        path = declared_node_path(attrs)
        if path:
            seen_paths.setdefault(path, []).append({"line": line_number, "name": attrs.get("name", ""), "parent": attrs.get("parent", "."), "type": attrs.get("type", "")})
    path_conflicts = [{"node_path": path, "declaration_count": len(declarations), "declarations": declarations} for path, declarations in sorted(seen_paths.items()) if len(declarations) > 1]
    return path_conflicts, attribute_conflicts, syntax_conflicts, malformed_header_conflicts


def _legacy_depth_only_accepts(value: str) -> bool:
    depth = 0
    in_string = False
    escaped = False
    for ch in value:
        if in_string:
            if escaped:
                escaped = False
            elif ch == '\\':
                escaped = True
            elif ch == '"':
                in_string = False
            continue
        if ch == '"':
            in_string = True
        elif ch in '([':
            depth += 1
        elif ch in ')]':
            if depth == 0:
                return False
            depth -= 1
    return depth == 0 and not in_string


def _v3_parser_accepts_trailing_structured_token(header: str) -> bool:
    """Reproduce the v3 blind spot: trailing text was swallowed into the value."""
    pairs: list[tuple[str, str]] = []
    i = 0
    n = len(header)
    while i < n:
        while i < n and header[i].isspace():
            i += 1
        if i >= n:
            break
        name_match = NAME_RE.match(header, i)
        if not name_match:
            return False
        name = name_match.group(0)
        i = name_match.end()
        while i < n and header[i].isspace():
            i += 1
        if i >= n or header[i] != '=':
            return False
        i += 1
        while i < n and header[i].isspace():
            i += 1
        value_start = i
        stack: list[str] = []
        in_string = False
        escaped = False
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
                elif ch in CLOSERS:
                    if not stack or stack[-1] != CLOSERS[ch]:
                        return False
                    stack.pop()
                elif ch.isspace() and not stack:
                    break
            i += 1
        if stack or in_string:
            return False
        value = header[value_start:i].strip()
        if not value:
            return False
        pairs.append((name, value))
    return bool(pairs)


def self_test() -> None:
    normal = '''
[gd_scene load_steps=1 format=3]
[node name="Main" type="Node3D"]
[node name="NpcAgent" type="CharacterBody3D" parent="."]
[node name="CharacterMount" type="Node3D" parent="NpcAgent"]
[node name="Skeleton3D" type="Skeleton3D" parent="NpcAgent/CharacterMount"]
[node name="Instance" parent="." instance=ExtResource("1_scene") groups=["ambient_pedestrian"]]
'''
    paths, attrs, syntax, malformed = node_table_conflicts(normal)
    assert paths == [] and attrs == [] and syntax == [] and malformed == []
    duplicate_path = normal + '[node name="CharacterMount" type="Node" parent="NpcAgent"]\n'
    legacy = skin.parse_node_blocks(duplicate_path)
    legacy_nodes: dict[str, dict[str, object]] = {}
    for block in legacy:
        block_attrs = block["attrs"]
        assert isinstance(block_attrs, dict)
        if "name" in block_attrs:
            legacy_nodes[skin.node_path(block_attrs)] = block
    assert legacy_nodes["NpcAgent/CharacterMount"]["attrs"]["type"] == "Node", "regression precondition: legacy node dict silently overwrites duplicate node paths"
    paths, attrs, syntax, malformed = node_table_conflicts(duplicate_path)
    assert len(paths) == 1 and paths[0]["node_path"] == "NpcAgent/CharacterMount" and attrs == [] and syntax == [] and malformed == []
    duplicate_name_attr = normal.replace('[node name="CharacterMount" type="Node3D" parent="NpcAgent"]','[node name="ForgedMount" name="CharacterMount" type="Node3D" parent="NpcAgent"]')
    paths, attrs, syntax, malformed = node_table_conflicts(duplicate_name_attr)
    assert paths == [] and syntax == [] and malformed == [] and len(attrs) == 1 and attrs[0]["duplicate_attributes"] == ["name"]
    partial = normal.replace('[node name="Skeleton3D" type="Skeleton3D" parent="NpcAgent/CharacterMount"]','[node name="Skeleton3D" type="Skeleton3D" parent="NpcAgent/CharacterMount" forged_token]')
    paths, attrs, syntax, malformed = node_table_conflicts(partial)
    assert paths == [] and attrs == [] and malformed == [] and len(syntax) == 1 and syntax[0]["unparsed_fragment"] == "forged_token"
    missing_close = normal.replace('[node name="CharacterMount" type="Node3D" parent="NpcAgent"]','[node name="CharacterMount" type="Node3D" parent="NpcAgent"')
    paths, attrs, syntax, malformed = node_table_conflicts(missing_close)
    assert paths == [] and attrs == [] and syntax == [] and len(malformed) == 1
    escaped_identity = normal + '[node name="Character\\u004dount" type="Node" parent="NpcAgent"]\n'
    legacy_escaped = skin.parse_node_blocks(escaped_identity)
    legacy_paths = [skin.node_path(block["attrs"]) for block in legacy_escaped if isinstance(block.get("attrs"), dict) and "name" in block["attrs"]]
    assert "NpcAgent/CharacterMount" in legacy_paths and "NpcAgent/Character\\u004dount" in legacy_paths, "regression precondition: legacy parser treats escaped and decoded node identities as distinct"
    paths, attrs, syntax, malformed = node_table_conflicts(escaped_identity)
    assert len(paths) == 1 and paths[0]["node_path"] == "NpcAgent/CharacterMount" and attrs == [] and syntax == [] and malformed == []
    malformed_escape = normal.replace('name="CharacterMount"', 'name="Character\\qMount"')
    paths, attrs, syntax, malformed = node_table_conflicts(malformed_escape)
    assert paths == [] and attrs == [] and malformed == [] and len(syntax) == 1, "invalid quoted escape must fail closed as unparsed syntax"

    mismatched_value = '(["ambient_pedestrian")]'
    assert _legacy_depth_only_accepts(mismatched_value), "regression precondition: v2 depth-only parser accepts cross-matched delimiters"
    mismatched_delimiters = normal.replace('groups=["ambient_pedestrian"]', f'groups={mismatched_value}')
    paths, attrs, syntax, malformed = node_table_conflicts(mismatched_delimiters)
    assert paths == [] and attrs == [] and malformed == [] and len(syntax) == 1, "cross-matched node-header delimiters must fail closed"

    forged_groups_header = 'name="Instance" parent="." groups=["ambient_pedestrian"]forged'
    assert _v3_parser_accepts_trailing_structured_token(forged_groups_header), "regression precondition: v3 swallows a token adjacent to a closed structured value"
    forged_groups = normal.replace('groups=["ambient_pedestrian"]', 'groups=["ambient_pedestrian"]forged')
    paths, attrs, syntax, malformed = node_table_conflicts(forged_groups)
    assert paths == [] and attrs == [] and malformed == [] and len(syntax) == 1 and "forged" in syntax[0]["unparsed_fragment"], "trailing token after array value must fail closed"

    forged_instance_header = 'name="Instance" parent="." instance=ExtResource("1_scene")forged'
    assert _v3_parser_accepts_trailing_structured_token(forged_instance_header), "regression precondition: v3 swallows a token adjacent to a closed call value"
    forged_instance = normal.replace('instance=ExtResource("1_scene")', 'instance=ExtResource("1_scene")forged')
    paths, attrs, syntax, malformed = node_table_conflicts(forged_instance)
    assert paths == [] and attrs == [] and malformed == [] and len(syntax) == 1 and "forged" in syntax[0]["unparsed_fragment"], "trailing token after call value must fail closed"


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        self_test()
        print("CIV1_NODE_TABLE_UNIQUENESS_SELF_TEST_OK")
        return 0
    if len(sys.argv) != 3:
        print("usage: civ1_node_table_uniqueness.py MAIN_TSCN OUT", file=sys.stderr)
        return 2
    main_tscn = Path(sys.argv[1]).resolve()
    out_path = Path(sys.argv[2])
    project_root = main_tscn.parent.parent
    scenes = skin.reachable_scenes(main_tscn, project_root)
    path_conflicts: list[dict[str, object]] = []
    attribute_conflicts: list[dict[str, object]] = []
    syntax_conflicts: list[dict[str, object]] = []
    malformed_header_conflicts: list[dict[str, object]] = []
    for scene_path in scenes:
        rel = scene_path.relative_to(project_root).as_posix()
        p, a, s, m = node_table_conflicts(scene_path.read_text(encoding="utf-8"))
        path_conflicts.extend({"scene": rel, **item} for item in p)
        attribute_conflicts.extend({"scene": rel, **item} for item in a)
        syntax_conflicts.extend({"scene": rel, **item} for item in s)
        malformed_header_conflicts.extend({"scene": rel, **item} for item in m)
    unambiguous = not path_conflicts and not attribute_conflicts and not syntax_conflicts and not malformed_header_conflicts
    result = {
        "schema": SCHEMA,
        "evidence_mode": "reachable_tscn_plus_unique_decoded_node_path_plus_complete_fully_parsed_unambiguous_node_headers_plus_type_matched_balanced_delimiters_plus_exact_structured_value_boundary",
        "reachable_scene_count": len(scenes),
        "duplicate_node_path_conflicts": path_conflicts,
        "duplicate_node_attribute_conflicts": attribute_conflicts,
        "unparsed_node_header_fragments": syntax_conflicts,
        "malformed_node_header_conflicts": malformed_header_conflicts,
        "node_paths_unique": not path_conflicts,
        "node_header_attributes_unambiguous": not attribute_conflicts,
        "node_header_syntax_fully_parsed": not syntax_conflicts,
        "node_header_delimiters_type_matched": not syntax_conflicts,
        "node_structured_value_boundaries_exact": not syntax_conflicts,
        "node_outer_header_syntax_valid": not malformed_header_conflicts,
        "node_table_identity_unambiguous": unambiguous,
        "duplicate_node_path_evidence_accepted": False,
        "duplicate_node_attribute_evidence_accepted": False,
        "escaped_node_identity_evidence_accepted": False,
        "partially_parsed_node_header_evidence_accepted": False,
        "mismatched_node_header_delimiter_evidence_accepted": False,
        "trailing_structured_value_token_evidence_accepted": False,
        "malformed_outer_node_header_evidence_accepted": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "contact_verified": False,
        "foot_slide_verified": False,
        "next_action": "remove duplicate decoded node paths/attributes, unparsed fragments, mismatched delimiters, trailing structured-value tokens and malformed node headers before authored Character hierarchy evidence can be trusted" if not unambiguous else "retain unique decoded fully parsed type-matched exact-boundary node-table gate before authored Character loaded-scene approval",
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
