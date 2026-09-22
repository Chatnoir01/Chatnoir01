#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path


def main() -> None:
    repo_root = Path(__file__).resolve().parents[2]
    status_path = repo_root / "grand-bruxelles-game/assets/characters/civilians/civ1/source_status.json"
    status = json.loads(status_path.read_text(encoding="utf-8"))

    assert status.get("candidate_id") == "CIV-1"
    assert status.get("excluded_upstream_intermediates") == [
        "godot_project/hairtool_cards.glb",
        "godot_project/vitruvian_hair.glb",
    ], "non-canonical upstream intermediates must remain explicitly excluded"

    character = status.get("character_source")
    assert isinstance(character, dict)
    license_evidence = character.get("license_evidence")
    assert isinstance(license_evidence, dict)
    assert license_evidence.get("tool_code_license") == "MIT", "upstream tool-code license must not be conflated with character geometry or animation payload terms"
    assert license_evidence.get("canonical_hair_asset") == "godot_project/vitruvian_hair_rigged.glb", "canonical rigged hair identity must remain explicit"

    sanitization = status.get("sanitization_contract")
    assert isinstance(sanitization, dict)
    assert sanitization.get("tool") == "tools/strip_glb_animations.py", "sanitization must stay bound to the reviewed stripper"
    assert sanitization.get("input_upstream_path") == "godot_project/vitruvian_body.glb", "sanitization input must stay bound to the pinned body payload"
    assert sanitization.get("operation") == "remove_glTF_animations_array_only"
    assert sanitization.get("preserve_non_json_chunks_byte_for_byte") is True
    assert sanitization.get("preserve_geometry_skin_material_json") is True
    assert sanitization.get("require_source_animations") is True
    assert sanitization.get("materialization_allowed_after_strip") is False
    assert sanitization.get("required_followup") == [
        "attach independently licensed idle/walk/run only after provenance verification",
        "grounding and foot-slide regression",
        "player-view 1280x720 evidence at 2m/5m/8m",
    ], "sanitization must not weaken the locomotion/grounding/player-view exit gate"

    print("CIV1_ROSTER_SANITIZATION_BOUNDARY_GREEN")


if __name__ == "__main__":
    main()
