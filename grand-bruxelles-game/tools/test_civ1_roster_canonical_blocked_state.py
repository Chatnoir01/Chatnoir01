#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

from civ1_roster_source_readiness import source_ready


def main() -> None:
    repo_root = Path(__file__).resolve().parents[2]
    status_path = repo_root / "grand-bruxelles-game/assets/characters/civilians/civ1/source_status.json"
    status = json.loads(status_path.read_text(encoding="utf-8"))

    assert status.get("candidate_id") == "CIV-1", "canonical blocked-state witness must remain bound to CIV-1"
    assert status.get("source_package_present") is False, "CIV-1 must not claim a source package while canonical source payloads are not materialized"
    assert status.get("runtime_package_present") is False, "CIV-1 must not claim a runtime package before independently licensed locomotion is integrated"
    assert status.get("activation_ready") is False, "CIV-1 must remain inactive while the runtime package is absent"
    assert status.get("production_authorized") is False, "CIV-1 must remain unauthorized while locomotion/grounding evidence is incomplete"
    blocker = status.get("blocker")
    assert isinstance(blocker, str) and blocker, "blocked CIV-1 must retain an explicit blocker"
    assert source_ready(repo_root) is False, "canonical CIV-1 source readiness must fail closed while runtime_package_present=false"

    character_source = status.get("character_source")
    assert isinstance(character_source, dict), "CIV-1 must retain canonical character-source provenance"
    assert character_source.get("repository") == "https://github.com/ibrews/VitruvianGodot", "CIV-1 character upstream repository must not drift silently"
    assert character_source.get("commit") == "bdecdcd537b4031fdd0fb299b7e4f93f084fffa0", "CIV-1 character upstream commit must remain pinned"
    license_evidence = character_source.get("license_evidence")
    assert isinstance(license_evidence, dict), "CIV-1 must retain component-level license evidence"
    assert license_evidence.get("character_geometry_license") == "CC0-1.0", "CIV-1 geometry license must remain explicit"
    assert license_evidence.get("character_geometry_redistribution_verified") is True, "CIV-1 geometry redistribution must remain verified"
    assert license_evidence.get("animation_payload_license") == "ADOBE_MIXAMO_TERMS", "embedded animation provenance must not be silently reclassified"
    assert license_evidence.get("unresolved_components") == ["godot_project/vitruvian_body.glb#embedded_mixamo_animations"], "unresolved Mixamo component identity must remain explicit until stripped/replaced"

    footwear_source = status.get("footwear_source")
    assert isinstance(footwear_source, dict), "CIV-1 must retain footwear provenance"
    assert footwear_source.get("repository") == "https://github.com/furqonat/makehuman-assets", "CIV-1 footwear upstream repository must not drift silently"
    assert footwear_source.get("commit") == "8cf9645b975a98eea056b140df11a1d278da0d10", "CIV-1 footwear upstream commit must remain pinned"
    assert footwear_source.get("asset") == "base/clothes/shoes03/shoes03.obj", "CIV-1 footwear asset identity must remain pinned"
    assert footwear_source.get("license") == "CC0-1.0", "CIV-1 footwear license must remain explicit"

    manifest = status.get("source_manifest")
    assert isinstance(manifest, dict), "CIV-1 must retain a source manifest"
    expected_blob_ids = {
        "assets/characters/civilians/civ1/source/vitruvian_body.glb": "09bcade1092e5a89b474e91e6013209d4c68c127",
        "assets/characters/civilians/civ1/source/vitruvian_head.glb": "0c810e209f09fc079086746f0813de9531d0f7fb",
        "assets/characters/civilians/civ1/source/vitruvian_hair_rigged.glb": "8edfccbf29e072b60b21a47dba9bbc992f00ac2e",
        "assets/characters/civilians/civ1/source/shoes03.obj": "2cd09f0af9c5bd13604d57d8af19e9205933ee85",
    }
    assert set(manifest) == set(expected_blob_ids), "canonical CIV-1 source-manifest membership must not drift silently"
    for source_path, blob_sha1 in expected_blob_ids.items():
        assert manifest[source_path].get("git_blob_sha1") == blob_sha1, f"canonical CIV-1 source blob identity drifted: {source_path}"
    assert manifest["assets/characters/civilians/civ1/source/vitruvian_body.glb"].get("license_scope_verified") is False, "body payload must remain blocked while embedded Mixamo animations are unresolved"
    assert manifest["assets/characters/civilians/civ1/source/vitruvian_body.glb"].get("geometry_license_scope_verified") is True, "body geometry license evidence must remain independently verified"

    sanitization = status.get("sanitization_contract")
    assert isinstance(sanitization, dict), "CIV-1 must retain its animation-stripping contract"
    assert sanitization.get("operation") == "remove_glTF_animations_array_only", "sanitization must remain limited to the glTF animations array"
    assert sanitization.get("preserve_non_json_chunks_byte_for_byte") is True, "sanitization must preserve non-JSON GLB chunks byte-for-byte"
    assert sanitization.get("preserve_geometry_skin_material_json") is True, "sanitization must preserve geometry/skin/material JSON"
    assert sanitization.get("require_source_animations") is True, "sanitization must fail closed if the blocked source animations are absent"
    assert sanitization.get("materialization_allowed_after_strip") is False, "animation stripping alone must never authorize source materialization"

    forbidden = status.get("forbidden_runtime_paths")
    assert isinstance(forbidden, list), "CIV-1 must retain an explicit forbidden-runtime path list"
    required_forbidden = {
        "assets/characters/player_character.glb",
        "assets/characters/player/",
    }
    assert required_forbidden.issubset(set(forbidden)), "player character file and player asset namespace must both stay forbidden for the CIV-1 civilian roster"
    assert status.get("mixamo_payload_allowed") is False, "unresolved Mixamo animation payload must remain forbidden from CIV-1 runtime promotion"

    sanitized = status.get("sanitized_body_evidence")
    assert isinstance(sanitized, dict), "CIV-1 must retain sanitized-body evidence while blocked"
    assert sanitized.get("binary_committed") is False, "sanitized CIV-1 binary must not become canonical before runtime promotion"
    assert sanitized.get("visual_approval_claimed") is False, "sanitized import evidence alone must never become visual approval"
    assert sanitized.get("sanitized_sha256") == "8601f55e7c54b104b5c67de27faa1415e060e16c6b22a32b1cc24e525fa88888", "canonical sanitized CIV-1 body identity must not drift before retarget evidence is regenerated"
    assert sanitized.get("counts") == {"meshes": 3, "skins": 1, "materials": 4}, "canonical sanitized CIV-1 mesh/skin/material inventory must not drift silently"

    import_evidence = status.get("godot_import_evidence")
    assert isinstance(import_evidence, dict), "CIV-1 must retain Godot import evidence while blocked"
    assert import_evidence.get("runtime_promoted") is False, "Godot import success must not silently promote CIV-1 runtime"
    assert import_evidence.get("visual_approval_claimed") is False, "Godot import success must not silently claim player-view approval"
    assert import_evidence.get("godot_version") == {"major": 4, "minor": 7, "patch": 1, "status": "stable"}, "CIV-1 import witness must remain qualified against exact Godot 4.7.1 stable"
    assert import_evidence.get("sanitized_body_sha256") == sanitized.get("sanitized_sha256"), "Godot import witness must refer to the exact canonical sanitized CIV-1 body"
    assert import_evidence.get("integrity") == "validated", "CIV-1 Godot import integrity must remain validated"
    assert import_evidence.get("counts") == {"skeletons": 1, "bones": 52, "mesh_instances": 3, "skinned_meshes": 3, "surfaces": 4, "material_surfaces": 4}, "CIV-1 Skeleton3D/skin/material import inventory must not drift before retargeting"

    next_gate = status.get("next_gate")
    assert isinstance(next_gate, str) and next_gate, "blocked CIV-1 must retain an explicit executable exit gate"
    required_exit_evidence = (
        "independently licensed idle/walk/run",
        "52-bone CIV-1 skeleton",
        "no foot sliding",
        "1280x720",
        "2m/5m/8m",
    )
    missing_exit_evidence = [witness for witness in required_exit_evidence if witness not in next_gate]
    assert not missing_exit_evidence, (
        "CIV-1 blocked-state exit gate must preserve locomotion, skeleton, grounding and player-view evidence requirements; "
        f"missing={missing_exit_evidence}"
    )

    print("CIV1_ROSTER_CANONICAL_BLOCKED_STATE_GREEN")


if __name__ == "__main__":
    main()
