#!/usr/bin/env python3
from copy import deepcopy
from pathlib import Path
import json
import sys

sys.path.insert(0, str(Path(__file__).parent))
from character_asset_intake_policy import UAL, _strict_json_loads, validate

AUDIT = Path(__file__).parents[1] / "qa" / "character_asset_store_audit_2026-09-20.json"
base = _strict_json_loads(AUDIT.read_text(encoding="utf-8"))
assert isinstance(base, dict)
assert validate(base) == [], validate(base)

# JSON's default last-key-wins behavior is unsafe for provenance: two textual
# claims for one payload must never collapse silently before validation.
for ambiguous in (
    '{"imported_payload_sha256":{"walk.glb":"' + "2" * 64 + '","walk.glb":"' + "3" * 64 + '"}}',
    '{"decision":"HOLD_FOR_LICENSE_SNAPSHOT_AND_RETARGET_AB","decision":"ADOPT"}',
):
    try:
        _strict_json_loads(ambiguous)
    except ValueError as exc:
        assert "duplicate JSON object key" in str(exc), exc
    else:
        raise AssertionError("duplicate JSON object key was silently accepted")


def candidate(doc):
    return next(c for c in doc["candidates"] if c["name"] == UAL)


def adopt_with_payloads(payloads):
    doc = deepcopy(base)
    c = candidate(doc)
    c["decision"] = "ADOPT"
    doc["adopted"] = [UAL]
    c.update({
        "license_snapshot_sha256": "0" * 64,
        "acquired_archive_sha256": "1" * 64,
        "imported_payload_sha256": payloads,
        "godot_4_7_1_qualified": True,
        "web_gl_qualified": True,
        "retarget_ab_qualified": True,
        "player_view_1280x720_qualified": True,
    })
    return doc

for mutation in ("decision", "adopted"):
    doc = deepcopy(base)
    if mutation == "decision": candidate(doc)["decision"] = "ADOPT"
    else: doc["adopted"] = [UAL]
    errors = validate(doc)
    assert errors, f"unsafe {mutation} flip was accepted"
    required = ("license_snapshot_sha256", "acquired_archive_sha256", "imported_payload_sha256",
                "godot_4_7_1_qualified", "web_gl_qualified", "retarget_ab_qualified",
                "player_view_1280x720_qualified")
    assert all(any(key in error for error in errors) for key in required), errors

doc = deepcopy(base)
c = candidate(doc); c["decision"] = "ADOPT"; doc["adopted"] = [UAL]
c.update({"license_snapshot_sha256":"0"*64,"acquired_archive_sha256":"1"*64,
          "imported_payload_sha256":{"walk.glb":"2"*64},"godot_4_7_1_qualified":1,
          "web_gl_qualified":"true","retarget_ab_qualified":[True],
          "player_view_1280x720_qualified":{"qualified":True}})
errors = validate(doc)
for key in ("godot_4_7_1_qualified","web_gl_qualified","retarget_ab_qualified","player_view_1280x720_qualified"):
    assert any(key in e for e in errors)

for unsafe_name in (".", "../walk.glb", "/tmp/walk.glb", "clips/../../walk.glb", "clips\\walk.glb", "",
                    "CON.glb", "clips/aux.txt", "walk.glb.", "walk.glb ", "C:walk.glb", "clips/wa\nlk.glb",
                    "clips/wa\x7flk.glb", "clips/wa\u0085lk.glb", "clips/wa\ud800lk.glb",
                    "clips/wa\u200blk.glb", "clips/wa\u202elk.glb", "clips/wa\u2066lk.glb",
                    "clips/wa\ufdd0lk.glb", "clips/wa\ufffelk.glb", "clips/wa\U0010fffflk.glb",
                    "clips/wa<lk.glb", "clips/wa>lk.glb", 'clips/wa"lk.glb', "clips/wa|lk.glb",
                    "clips/wa?lk.glb", "clips/wa*lk.glb", "clips/COM¹.glb", "clips/com².GLB",
                    "clips/LPT³.anim", "clips/CONIN$.glb", "clips/conout$.anim",
                    "clips//walk.glb", "clips/./walk.glb", "clips/walk.glb/",
                    "clips/cafe\u0301.glb",
                    "clips/" + "a" * 256,
                    "clips/" + "é" * 128):
    errors = validate(adopt_with_payloads({unsafe_name: "2" * 64}))
    assert any("safe canonical portable relative POSIX path" in e for e in errors), (repr(unsafe_name), errors)

assert validate(adopt_with_payloads({"clips/caf\u00e9.glb": "2" * 64})) == []
assert validate(adopt_with_payloads({"clips/" + "a" * 255: "2" * 64})) == []

for colliding in (
    {"clips/Walk.glb": "2" * 64, "clips/walk.glb": "3" * 64},
):
    errors = validate(adopt_with_payloads(colliding))
    assert any("Unicode NFC + casefold" in e for e in errors), errors

assert validate(adopt_with_payloads({"locomotion/walk.glb": "2" * 64})) == []

for field, value in (("pack_specific_license_claim", "QAL-1.0"),
                     ("publisher_general_license_current", "QAL-2.0")):
    doc = deepcopy(base); candidate(doc)[field] = value
    assert validate(doc), f"license drift in {field} was accepted"

print("PASS: Character asset intake fail-closed regression")
