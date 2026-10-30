#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path


def main() -> None:
    repo_root = Path(__file__).resolve().parents[2]
    status_path = repo_root / "grand-bruxelles-game/assets/characters/civilians/civ1/source_status.json"
    status = json.loads(status_path.read_text(encoding="utf-8"))

    assert status.get("candidate_id") == "CIV-1"
    assert status.get("source_paths") == [
        "assets/characters/civilians/civ1/source/vitruvian_body.glb",
        "assets/characters/civilians/civ1/source/vitruvian_head.glb",
        "assets/characters/civilians/civ1/source/vitruvian_hair_rigged.glb",
        "assets/characters/civilians/civ1/source/shoes03.obj",
    ], "canonical source-path order/membership must remain explicit"

    character = status["character_source"]
    assert character["repository"] == "https://github.com/ibrews/VitruvianGodot"
    assert character["commit"] == "bdecdcd537b4031fdd0fb299b7e4f93f084fffa0"
    assert character["license_claim"] == "MIXED_BY_COMPONENT"
    license_evidence = character["license_evidence"]
    assert license_evidence["license_path"] == "LICENSE"
    assert license_evidence["license_git_blob_sha1"] == "d6649f9dae1675ae1a8a0d1fb64163b420064e64"
    assert license_evidence["notice_path"] == "NOTICE.md"
    assert license_evidence["notice_git_blob_sha1"] == "ea2ccd72bd82dc0d97427e02a3eb1f03e06c3e68"
    assert license_evidence["readme_path"] == "README.md"
    assert license_evidence["readme_git_blob_sha1"] == "53462ca128e2a5a44fac2477a41bdc843cdae2d7"
    assert license_evidence["character_geometry_license"] == "CC0-1.0"
    assert license_evidence["character_geometry_redistribution_verified"] is True
    assert license_evidence["animation_payload_license"] == "ADOBE_MIXAMO_TERMS"
    assert license_evidence["unresolved_components"] == ["godot_project/vitruvian_body.glb#embedded_mixamo_animations"]
    assert license_evidence["canonical_hair_asset"] == "godot_project/vitruvian_hair_rigged.glb"

    footwear = status["footwear_source"]
    assert footwear["repository"] == "https://github.com/furqonat/makehuman-assets"
    assert footwear["commit"] == "8cf9645b975a98eea056b140df11a1d278da0d10"
    assert footwear["asset"] == "base/clothes/shoes03/shoes03.obj"
    assert footwear["license"] == "CC0-1.0"
    assert footwear["obj_git_blob_sha1"] == "2cd09f0af9c5bd13604d57d8af19e9205933ee85"

    manifest = status["source_manifest"]
    expected = {
        "assets/characters/civilians/civ1/source/vitruvian_body.glb": ("godot_project/vitruvian_body.glb", "09bcade1092e5a89b474e91e6013209d4c68c127", 6879364),
        "assets/characters/civilians/civ1/source/vitruvian_head.glb": ("godot_project/vitruvian_head.glb", "0c810e209f09fc079086746f0813de9531d0f7fb", 10189832),
        "assets/characters/civilians/civ1/source/vitruvian_hair_rigged.glb": ("godot_project/vitruvian_hair_rigged.glb", "8edfccbf29e072b60b21a47dba9bbc992f00ac2e", 37694332),
        "assets/characters/civilians/civ1/source/shoes03.obj": ("base/clothes/shoes03/shoes03.obj", "2cd09f0af9c5bd13604d57d8af19e9205933ee85", None),
    }
    assert set(manifest) == set(expected)
    for local_path, (upstream_path, blob_sha1, size_bytes) in expected.items():
        entry = manifest[local_path]
        assert entry["upstream_path"] == upstream_path, f"upstream path drifted: {local_path}"
        assert entry["git_blob_sha1"] == blob_sha1, f"upstream blob drifted: {local_path}"
        assert entry["size_bytes"] == size_bytes, f"source size drifted: {local_path}"

    body = manifest["assets/characters/civilians/civ1/source/vitruvian_body.glb"]
    assert body["license_scope_verified"] is False
    assert body["geometry_license_scope_verified"] is True
    assert body["blocked_component"] == "embedded_mixamo_animations"
    for local_path in (
        "assets/characters/civilians/civ1/source/vitruvian_head.glb",
        "assets/characters/civilians/civ1/source/vitruvian_hair_rigged.glb",
        "assets/characters/civilians/civ1/source/shoes03.obj",
    ):
        assert manifest[local_path]["license_scope_verified"] is True
        assert manifest[local_path]["license"] == "CC0-1.0"

    sanitized = status["sanitized_body_evidence"]
    assert sanitized["evidence_workflow"] == "Grand Bruxelles CIV-1 Body Sanitization Evidence", "sanitized evidence must stay bound to the qualified workflow identity"
    assert sanitized["workflow_run_id"] == 33333132726
    assert sanitized["artifact_id"] == 9738218858
    assert sanitized["artifact_zip_sha256"] == "727a316a0fc5d76284882fb4216699f04a3ba958b47daa45f5f8d50dba6fae53"
    assert sanitized["source_git_blob_sha1"] == manifest["assets/characters/civilians/civ1/source/vitruvian_body.glb"]["git_blob_sha1"]
    assert sanitized["source_size_bytes"] == manifest["assets/characters/civilians/civ1/source/vitruvian_body.glb"]["size_bytes"]
    assert sanitized["animations_removed"] == 6
    assert sanitized["sanitized_size_bytes"] == 6780124
    assert sanitized["reference_integrity"] == "validated"

    imported = status["godot_import_evidence"]
    assert imported["evidence_workflow"] == "Grand Bruxelles CIV-1 Godot Import Evidence", "import evidence must stay bound to the qualified workflow identity"
    assert imported["workflow_run_id"] == 33347264748
    assert imported["artifact_id"] == 9742392461
    assert imported["artifact_zip_sha256"] == "a25f1df57c04fc6c208f59e07596e979897050e29481833bcc90604df1772aac"
    assert imported["godot_linux_zip_sha256"] == "c7ff14fd28472c8d4f193043de30278dcf7e5241a1dcf7566b02e27addaa33ba"
    assert imported["sanitized_body_sha256"] == sanitized["sanitized_sha256"]
    assert imported["sanitized_body_size_bytes"] == sanitized["sanitized_size_bytes"]
    assert imported["binary_committed"] is False

    assert status["runtime_files"] == ["assets/characters/civilians/civ1/civ1.tscn"]
    assert status["runtime_sha256"] == {}, "blocked CIV-1 must not acquire an unverified runtime hash"
    print("CIV1_ROSTER_EVIDENCE_BINDING_GREEN")


if __name__ == "__main__":
    main()
