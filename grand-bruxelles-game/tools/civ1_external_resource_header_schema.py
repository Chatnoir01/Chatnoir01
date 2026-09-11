#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from collections import Counter
from pathlib import Path

import civ1_authored_skin_integrity as skin
import civ1_resource_table_uniqueness as table

SCHEMA = "grand-bruxelles-civ1-external-resource-header-schema-v3"
REQUIRED_ATTRIBUTES = frozenset({"type", "path", "id"})
OPTIONAL_ATTRIBUTES = frozenset({"uid"})
ALLOWED_ATTRIBUTES = REQUIRED_ATTRIBUTES | OPTIONAL_ATTRIBUTES
LEGACY_UID_TEXT_RE = re.compile(r"uid://[a-z0-9]+")
GODOT_UID_ALPHABET = "abcdefghijklmnopqrstuvwxy012345678"
GODOT_UID_BASE = len(GODOT_UID_ALPHABET)
GODOT_UID_MAX_ID = 0x7FFFFFFFFFFFFFFF
UINT64_MASK = 0xFFFFFFFFFFFFFFFF


def _godot_uid_text_to_id(value: str) -> int | None:
    """Mirror ResourceUID::text_to_id enough to prove text canonicality."""
    if not value.startswith("uid://") or value == "uid://<invalid>":
        return None
    uid = 0
    for char in value[6:]:
        uid = (uid * GODOT_UID_BASE) & UINT64_MASK
        if "a" <= char <= "z":
            digit = ord(char) - ord("a")
        elif "0" <= char <= "9":
            digit = ord(char) - ord("0") + 25
        else:
            return None
        uid = (uid + digit) & UINT64_MASK
    return uid & GODOT_UID_MAX_ID


def _godot_uid_id_to_text(uid: int) -> str:
    if uid < 0:
        return "uid://<invalid>"
    chars: list[str] = []
    while True:
        chars.append(GODOT_UID_ALPHABET[uid % GODOT_UID_BASE])
        uid //= GODOT_UID_BASE
        if not uid:
            break
    return "uid://" + "".join(reversed(chars))


def legacy_uid_regex_evidence_accepted(value: str) -> bool:
    """v2 lexical rule: lowercase letters/digits after uid://, without engine round-trip."""
    return LEGACY_UID_TEXT_RE.fullmatch(value) is not None


def uid_text_is_lexically_canonical(value: str) -> bool:
    uid = _godot_uid_text_to_id(value)
    return uid is not None and _godot_uid_id_to_text(uid) == value


def external_resource_header_conflicts(scene_text: str) -> list[dict[str, object]]:
    conflicts: list[dict[str, object]] = []
    for line_number, line in enumerate(scene_text.splitlines(), start=1):
        match = table.EXT_RE.match(line)
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
        empty_required = sorted(name for name in REQUIRED_ATTRIBUTES if name in attrs and not attrs[name])
        uid_value = attrs.get("uid")
        invalid_uid = uid_value is not None and not uid_text_is_lexically_canonical(uid_value)
        if missing:
            reasons.append("missing_required_attribute")
        if foreign:
            reasons.append("foreign_header_attribute")
        if empty_required:
            reasons.append("empty_required_attribute")
        if invalid_uid:
            reasons.append("invalid_uid_attribute")
        if reasons:
            conflicts.append({
                "line": line_number,
                "raw_header": line.strip(),
                "reasons": reasons,
                "missing_attributes": missing,
                "foreign_attributes": foreign,
                "empty_required_attributes": empty_required,
                "invalid_uid": invalid_uid,
            })
    return conflicts


def legacy_foreign_attribute_evidence_accepted(scene_text: str) -> bool:
    ids, attrs, syntax, malformed = table.resource_table_conflicts(scene_text)
    parsed = skin.parse_resource_table(scene_text)
    ext = parsed.get(("ExtResource", "Skin_body"))
    return (
        not ids and not attrs and not syntax and not malformed
        and isinstance(ext, dict)
        and ext.get("type") == "Skin"
        and ext.get("path") == "res://assets/body.skin"
    )


def legacy_uid_prefix_evidence_accepted(value: str) -> bool:
    return bool(value) and value.startswith("uid://")


def self_test() -> None:
    canonical_uid = "uid://civ1skin"
    assert uid_text_is_lexically_canonical(canonical_uid)
    canonical = f'''
[gd_scene format=3]
[ext_resource type="Skin" uid="{canonical_uid}" path="res://assets/body.skin" id="Skin_body"]
[node name="Main" type="Node3D"]
'''
    assert external_resource_header_conflicts(canonical) == []
    no_uid = canonical.replace(f' uid="{canonical_uid}"', '')
    assert external_resource_header_conflicts(no_uid) == []

    foreign = canonical.replace(' id="Skin_body"]', ' forged="yes" id="Skin_body"]')
    assert legacy_foreign_attribute_evidence_accepted(foreign), "causal precondition: retained resource-table evidence ignores a foreign ext_resource attribute"
    assert external_resource_header_conflicts(foreign), "foreign ext_resource attributes must fail closed"

    malformed_uid = "uid://NOT_VALID"
    assert legacy_uid_prefix_evidence_accepted(malformed_uid), "causal precondition: v1 accepted any non-empty uid:// prefix"
    malformed_uid_scene = canonical.replace(canonical_uid, malformed_uid)
    malformed_conflicts = external_resource_header_conflicts(malformed_uid_scene)
    assert malformed_conflicts and "invalid_uid_attribute" in malformed_conflicts[0]["reasons"]

    # v2 accepted lowercase/digit strings that are not canonical ResourceUID text.
    # Godot's encoder uses a 34-character output alphabet (a-y, 0-8); text_to_id
    # also parses z/9 and leading-zero aliases, so only round-trip equality closes them.
    for noncanonical_uid in ("uid://abc", "uid://z", "uid://9", "uid://aciv1skin"):
        assert legacy_uid_regex_evidence_accepted(noncanonical_uid), noncanonical_uid
        assert not uid_text_is_lexically_canonical(noncanonical_uid), noncanonical_uid
        scene = canonical.replace(canonical_uid, noncanonical_uid)
        conflicts = external_resource_header_conflicts(scene)
        assert conflicts and "invalid_uid_attribute" in conflicts[0]["reasons"], noncanonical_uid

    cases = {
        "missing_type": canonical.replace('type="Skin" ', ''),
        "missing_path": canonical.replace(' path="res://assets/body.skin"', ''),
        "missing_id": canonical.replace(' id="Skin_body"', ''),
        "empty_type": canonical.replace('type="Skin"', 'type=""'),
        "empty_path": canonical.replace('path="res://assets/body.skin"', 'path=""'),
        "empty_id": canonical.replace('id="Skin_body"', 'id=""'),
        "empty_uid": canonical.replace(canonical_uid, ''),
        "prefix_only_uid": canonical.replace(canonical_uid, 'uid://'),
        "uppercase_uid": canonical.replace(canonical_uid, 'uid://CIV1SKIN'),
        "punctuated_uid": canonical.replace(canonical_uid, 'uid://civ1_skin'),
        "invalid_sentinel_uid": canonical.replace(canonical_uid, 'uid://<invalid>'),
        "malformed_uid": canonical.replace(canonical_uid, 'not-a-uid'),
    }
    for label, text in cases.items():
        assert external_resource_header_conflicts(text), label


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        self_test()
        print("CIV1_EXTERNAL_RESOURCE_HEADER_SCHEMA_SELF_TEST_OK")
        return 0
    if len(sys.argv) != 3:
        print("usage: civ1_external_resource_header_schema.py MAIN_TSCN OUT", file=sys.stderr)
        return 2

    main_tscn = Path(sys.argv[1]).resolve()
    out_path = Path(sys.argv[2])
    project_root = main_tscn.parent.parent
    scenes = skin.reachable_scenes(main_tscn, project_root)
    conflicts: list[dict[str, object]] = []
    for scene_path in scenes:
        rel = scene_path.relative_to(project_root).as_posix()
        for conflict in external_resource_header_conflicts(scene_path.read_text(encoding="utf-8")):
            conflicts.append({"scene": rel, **conflict})

    result = {
        "schema": SCHEMA,
        "evidence_mode": "reachable_tscn_plus_closed_external_resource_header_attribute_and_godot_roundtrip_uid_schema",
        "reachable_scene_count": len(scenes),
        "external_resource_header_schema_conflicts": conflicts,
        "external_resource_header_schema_canonical": not conflicts,
        "foreign_external_resource_header_evidence_accepted": False,
        "external_resource_missing_required_attribute_evidence_accepted": False,
        "external_resource_empty_required_attribute_evidence_accepted": False,
        "external_resource_invalid_uid_evidence_accepted": False,
        "external_resource_malformed_uid_payload_evidence_accepted": False,
        "external_resource_noncanonical_uid_alias_evidence_accepted": False,
        "external_resource_uid_lexemes_canonical": not any(c.get("invalid_uid") for c in conflicts),
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "contact_verified": False,
        "foot_slide_verified": False,
        "next_action": "retain closed type+path+id headers and Godot-roundtrip-canonical optional uid lexemes before authored Character loaded-scene approval" if not conflicts else "remove foreign, missing, empty or invalid external-resource header attributes and noncanonical uid aliases before Character evidence can be trusted",
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
