#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from collections import Counter
from pathlib import Path

import civ1_authored_skin_integrity as skin

SCHEMA = "grand-bruxelles-civ1-subresource-property-uniqueness-v1"
SUBRESOURCE_RE = re.compile(r'^\s*\[sub_resource\s+(.+?)\]\s*$')
ID_RE = re.compile(r'(?:^|\s)id\s*=\s*"([^"]+)"')


def property_conflicts(scene_text: str) -> list[dict[str, object]]:
    conflicts: list[dict[str, object]] = []
    current: dict[str, object] | None = None
    for line_number, line in enumerate(scene_text.splitlines(), start=1):
        match = SUBRESOURCE_RE.match(line)
        if match:
            if current is not None:
                conflicts.extend(_duplicates_for_subresource(current))
            header = match.group(1)
            id_match = ID_RE.search(header)
            current = {
                "line": line_number,
                "id": id_match.group(1) if id_match else "<unresolved-subresource>",
                "properties": [],
            }
            continue
        if line.lstrip().startswith("["):
            if current is not None:
                conflicts.extend(_duplicates_for_subresource(current))
            current = None
            continue
        if current is None or "=" not in line:
            continue
        key, _ = line.split("=", 1)
        key = key.strip()
        if key:
            properties = current["properties"]
            assert isinstance(properties, list)
            properties.append((key, line_number))
    if current is not None:
        conflicts.extend(_duplicates_for_subresource(current))
    return conflicts


def _duplicates_for_subresource(subresource: dict[str, object]) -> list[dict[str, object]]:
    properties = subresource["properties"]
    assert isinstance(properties, list)
    counts = Counter(key for key, _ in properties)
    out: list[dict[str, object]] = []
    for key in sorted(name for name, count in counts.items() if count > 1):
        out.append({
            "subresource_id": subresource["id"],
            "subresource_header_line": subresource["line"],
            "property": key,
            "assignment_count": counts[key],
            "assignment_lines": [line for name, line in properties if name == key],
            "reason": "duplicate_property_assignment_in_single_subresource_block",
        })
    return out


def _legacy_subresource_property_dict(scene_text: str, target_id: str) -> dict[str, str]:
    current_id: str | None = None
    target_props: dict[str, str] = {}
    for line in scene_text.splitlines():
        match = SUBRESOURCE_RE.match(line)
        if match:
            id_match = ID_RE.search(match.group(1))
            current_id = id_match.group(1) if id_match else None
            continue
        if line.lstrip().startswith("["):
            current_id = None
            continue
        if current_id != target_id or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        if key:
            target_props[key] = value.strip()
    return target_props


def self_test() -> None:
    normal = '''
[gd_scene load_steps=2 format=3]
[sub_resource type="ArrayMesh" id="Mesh_body"]
resource_name = "body"
resource_local_to_scene = true
[node name="Main" type="Node3D"]
'''
    assert property_conflicts(normal) == []

    forged = normal.replace(
        'resource_name = "body"',
        'resource_name = "stale"\nresource_name = "body"',
    )
    legacy = _legacy_subresource_property_dict(forged, "Mesh_body")
    assert legacy.get("resource_name") == '"body"', "regression precondition: dict-style subresource parsing silently keeps only the last duplicate property assignment"
    conflicts = property_conflicts(forged)
    assert len(conflicts) == 1
    assert conflicts[0]["subresource_id"] == "Mesh_body"
    assert conflicts[0]["property"] == "resource_name"
    assert conflicts[0]["assignment_count"] == 2

    separate = '''
[sub_resource type="ArrayMesh" id="Mesh_a"]
resource_name = "a"
[sub_resource type="ArrayMesh" id="Mesh_b"]
resource_name = "b"
'''
    assert property_conflicts(separate) == [], "the same property on distinct subresources must remain valid"

    section_reset = '''
[sub_resource type="ArrayMesh" id="Mesh_a"]
resource_name = "a"
[node name="Main" type="Node3D"]
resource_name = "not-a-subresource-property"
'''
    assert property_conflicts(section_reset) == [], "a new non-subresource section must terminate the tracked subresource block"


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        self_test()
        print("CIV1_SUBRESOURCE_PROPERTY_UNIQUENESS_SELF_TEST_OK")
        return 0
    if len(sys.argv) != 3:
        print("usage: civ1_subresource_property_uniqueness.py MAIN_TSCN OUT", file=sys.stderr)
        return 2

    main_tscn = Path(sys.argv[1]).resolve()
    out_path = Path(sys.argv[2])
    project_root = main_tscn.parent.parent
    scenes = skin.reachable_scenes(main_tscn, project_root)
    conflicts: list[dict[str, object]] = []
    for scene_path in scenes:
        rel = scene_path.relative_to(project_root).as_posix()
        conflicts.extend({"scene": rel, **item} for item in property_conflicts(scene_path.read_text(encoding="utf-8")))

    result = {
        "schema": SCHEMA,
        "evidence_mode": "reachable_tscn_plus_unique_property_assignment_per_subresource_block",
        "reachable_scene_count": len(scenes),
        "duplicate_subresource_property_conflicts": conflicts,
        "subresource_property_assignments_unique": not conflicts,
        "duplicate_subresource_property_evidence_accepted": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "contact_verified": False,
        "foot_slide_verified": False,
        "next_action": "remove duplicate subresource property assignments before authored Character integrity evidence can be trusted" if conflicts else "retain subresource-property uniqueness gate before authored Character loaded-scene approval",
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
