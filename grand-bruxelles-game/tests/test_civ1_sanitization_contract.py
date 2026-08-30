#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STATUS = json.loads((ROOT / "assets/characters/civilians/civ1/source_status.json").read_text(encoding="utf-8"))


def test_sanitization_contract_is_fail_closed() -> None:
    contract = STATUS["sanitization_contract"]
    assert contract["tool"] == "tools/strip_glb_animations.py"
    assert contract["input_upstream_path"] == "godot_project/vitruvian_body.glb"
    assert contract["operation"] == "remove_glTF_animations_array_only"
    assert contract["preserve_non_json_chunks_byte_for_byte"] is True
    assert contract["preserve_geometry_skin_material_json"] is True
    assert contract["require_source_animations"] is True
    assert contract["materialization_allowed_after_strip"] is False
    assert STATUS["mixamo_payload_allowed"] is False
    assert STATUS["source_package_present"] is False
    assert STATUS["runtime_package_present"] is False
    assert STATUS["production_authorized"] is False
    assert STATUS["activation_ready"] is False


def test_body_pin_still_names_embedded_animation_blocker() -> None:
    body = STATUS["source_manifest"]["assets/characters/civilians/civ1/source/vitruvian_body.glb"]
    assert body["git_blob_sha1"] == "09bcade1092e5a89b474e91e6013209d4c68c127"
    assert body["size_bytes"] == 6879364
    assert body["license_scope_verified"] is False
    assert body["geometry_license_scope_verified"] is True
    assert body["blocked_component"] == "embedded_mixamo_animations"


def test_followup_requires_integrity_locomotion_and_player_view_evidence() -> None:
    text = "\n".join(STATUS["sanitization_contract"]["required_followup"]).lower()
    for required in ("git blob", "sha-256", "skeleton", "skin", "material", "idle/walk/run", "foot-slide", "1280x720", "2m/5m/8m"):
        assert required.lower() in text, required


def test_tool_exists_in_repo() -> None:
    assert (ROOT / STATUS["sanitization_contract"]["tool"]).is_file()


def main() -> int:
    tests = [test_sanitization_contract_is_fail_closed, test_body_pin_still_names_embedded_animation_blocker, test_followup_requires_integrity_locomotion_and_player_view_evidence, test_tool_exists_in_repo]
    for test in tests:
        test(); print(f"PASS {test.__name__}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
