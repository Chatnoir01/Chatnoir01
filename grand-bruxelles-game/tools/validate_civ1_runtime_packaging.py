#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

EXPECTED = {
    "candidate_id": "CIV-1",
    "owner_verdict": "GARDER",
    "approved_review_pr": 1006,
    "character_repo": "https://github.com/ibrews/VitruvianGodot",
    "character_commit": "bdecdcd537b4031fdd0fb299b7e4f93f084fffa0",
    "footwear_repo": "https://github.com/furqonat/makehuman-assets",
    "footwear_commit": "8cf9645b975a98eea056b140df11a1d278da0d10",
    "footwear_asset": "base/clothes/shoes03/shoes03.obj",
    "footwear_blob": "2cd09f0af9c5bd13604d57d8af19e9205933ee85",
}
EXPECTED_EVIDENCE = {
    "license_path": "LICENSE",
    "license_git_blob_sha1": "d6649f9dae1675ae1a8a0d1fb64163b420064e64",
    "notice_path": "NOTICE.md",
    "notice_git_blob_sha1": "ea2ccd72bd82dc0d97427e02a3eb1f03e06c3e68",
    "readme_path": "README.md",
    "readme_git_blob_sha1": "53462ca128e2a5a44fac2477a41bdc843cdae2d7",
    "character_geometry_license": "CC0-1.0",
    "character_geometry_redistribution_verified": True,
    "tool_code_license": "MIT",
    "animation_payload_license": "ADOBE_MIXAMO_TERMS",
    "unresolved_components": ["godot_project/vitruvian_body.glb#embedded_mixamo_animations"],
    "canonical_hair_asset": "godot_project/vitruvian_hair_rigged.glb",
}
EXPECTED_SOURCE_MANIFEST = {
    "assets/characters/civilians/civ1/source/vitruvian_body.glb": {
        "upstream_path": "godot_project/vitruvian_body.glb",
        "git_blob_sha1": "09bcade1092e5a89b474e91e6013209d4c68c127",
        "size_bytes": 6879364,
        "license_scope_verified": False,
        "geometry_license_scope_verified": True,
        "blocked_component": "embedded_mixamo_animations",
    },
    "assets/characters/civilians/civ1/source/vitruvian_head.glb": {
        "upstream_path": "godot_project/vitruvian_head.glb",
        "git_blob_sha1": "0c810e209f09fc079086746f0813de9531d0f7fb",
        "size_bytes": 10189832,
        "license_scope_verified": True,
        "license": "CC0-1.0",
    },
    "assets/characters/civilians/civ1/source/vitruvian_hair_rigged.glb": {
        "upstream_path": "godot_project/vitruvian_hair_rigged.glb",
        "git_blob_sha1": "8edfccbf29e072b60b21a47dba9bbc992f00ac2e",
        "size_bytes": 37694332,
        "license_scope_verified": True,
        "license": "CC0-1.0",
    },
    "assets/characters/civilians/civ1/source/shoes03.obj": {
        "upstream_path": "base/clothes/shoes03/shoes03.obj",
        "git_blob_sha1": "2cd09f0af9c5bd13604d57d8af19e9205933ee85",
        "size_bytes": None,
        "license_scope_verified": True,
        "license": "CC0-1.0",
    },
}
EXPECTED_EXCLUDED = ["godot_project/hairtool_cards.glb", "godot_project/vitruvian_hair.glb"]


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _git_blob_sha1(path: Path) -> str:
    size = path.stat().st_size
    digest = hashlib.sha1()
    digest.update(f"blob {size}\0".encode("ascii"))
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _load_status(root: Path) -> dict:
    path = root / "assets/characters/civilians/civ1/source_status.json"
    if not path.is_file():
        raise FileNotFoundError(path)
    return json.loads(path.read_text(encoding="utf-8"))


def validate(root: Path, require_ready: bool = False) -> list[str]:
    errors: list[str] = []
    try:
        status = _load_status(root)
    except (FileNotFoundError, json.JSONDecodeError) as exc:
        return [f"cannot load CIV-1 source status: {exc}"]

    for key in ("candidate_id", "owner_verdict", "approved_review_pr"):
        if status.get(key) != EXPECTED[key]:
            errors.append(f"{key} must be {EXPECTED[key]!r}")

    character = status.get("character_source", {})
    footwear = status.get("footwear_source", {})
    if character.get("repository") != EXPECTED["character_repo"]: errors.append("character source repository drift")
    if character.get("commit") != EXPECTED["character_commit"]: errors.append("character source commit drift")
    if character.get("license_claim") != "MIXED_BY_COMPONENT": errors.append("character source license claim must remain MIXED_BY_COMPONENT")
    evidence = character.get("license_evidence")
    if not isinstance(evidence, dict):
        errors.append("character source license evidence missing")
        evidence = {}
    for key, expected in EXPECTED_EVIDENCE.items():
        if evidence.get(key) != expected:
            errors.append(f"character source license evidence drift: {key}")

    if footwear.get("repository") != EXPECTED["footwear_repo"]: errors.append("footwear source repository drift")
    if footwear.get("commit") != EXPECTED["footwear_commit"]: errors.append("footwear source commit drift")
    if footwear.get("asset") != EXPECTED["footwear_asset"]: errors.append("footwear source asset drift")
    if footwear.get("obj_git_blob_sha1") != EXPECTED["footwear_blob"]: errors.append("footwear blob pin drift")
    if footwear.get("license") != "CC0-1.0": errors.append("footwear source must remain CC0-1.0")
    if status.get("mixamo_payload_allowed") is not False: errors.append("Mixamo-derived payload must remain excluded")
    if status.get("excluded_upstream_intermediates") != EXPECTED_EXCLUDED: errors.append("excluded upstream hair intermediates drift")

    source_paths = status.get("source_paths")
    source_manifest = status.get("source_manifest")
    runtime_files = status.get("runtime_files")
    runtime_scene = status.get("runtime_scene")
    runtime_hashes = status.get("runtime_sha256")
    forbidden = status.get("forbidden_runtime_paths")

    if source_paths != list(EXPECTED_SOURCE_MANIFEST): errors.append("source_paths must match the immutable CIV-1 source manifest order")
    if not isinstance(source_manifest, dict):
        errors.append("source_manifest must be an object")
        source_manifest = {}
    if set(source_manifest) != set(EXPECTED_SOURCE_MANIFEST): errors.append("source_manifest paths drift from immutable CIV-1 pins")
    for rel, expected_pin in EXPECTED_SOURCE_MANIFEST.items():
        if source_manifest.get(rel) != expected_pin:
            errors.append(f"source manifest pin drift: {rel}")

    canonical_prefix = "assets/characters/civilians/civ1/"
    player_forbidden = ("assets/characters/player_character.glb", "assets/characters/player/")
    if not isinstance(forbidden, list): forbidden = []
    for required in player_forbidden:
        if required not in forbidden: errors.append(f"missing forbidden player path: {required}")
    if not isinstance(runtime_scene, str) or not runtime_scene.startswith(canonical_prefix): errors.append("runtime_scene must live under the canonical CIV-1 directory")
    if not isinstance(runtime_files, list) or not runtime_files: errors.append("runtime_files must be a non-empty list")
    else:
        for rel in runtime_files:
            if not isinstance(rel, str) or not rel.startswith(canonical_prefix): errors.append(f"runtime file escapes canonical CIV-1 directory: {rel!r}")
            if rel == player_forbidden[0] or rel.startswith(player_forbidden[1]): errors.append(f"player character reuse is forbidden: {rel}")
        if runtime_scene not in runtime_files: errors.append("runtime_scene must be listed in runtime_files")
    if not isinstance(runtime_hashes, dict):
        errors.append("runtime_sha256 must be an object")
        runtime_hashes = {}

    source_present = status.get("source_package_present") is True
    runtime_present = status.get("runtime_package_present") is True
    authorized = status.get("production_authorized") is True
    ready = status.get("activation_ready") is True

    if source_present:
        unresolved = [rel for rel, pin in source_manifest.items() if pin.get("license_scope_verified") is not True]
        if unresolved: errors.append("source materialization requires verified license scope for every source blob")
        if evidence.get("unresolved_components"): errors.append("source materialization forbidden while character license components remain unresolved")
        for rel in source_paths or []:
            target = root / rel
            if not target.is_file():
                errors.append(f"declared source file missing: {rel}")
                continue
            expected_pin = EXPECTED_SOURCE_MANIFEST.get(rel)
            if expected_pin is None:
                errors.append(f"unrecognized source file: {rel}")
                continue
            expected_size = expected_pin.get("size_bytes")
            if isinstance(expected_size, int) and target.stat().st_size != expected_size: errors.append(f"source size mismatch for {rel}: expected {expected_size}, got {target.stat().st_size}")
            if _git_blob_sha1(target) != expected_pin["git_blob_sha1"]: errors.append(f"source git blob mismatch for {rel}")

    if runtime_present and isinstance(runtime_files, list):
        for rel in runtime_files:
            target = root / rel
            if not target.is_file():
                errors.append(f"declared runtime file missing: {rel}")
                continue
            expected_hash = runtime_hashes.get(rel)
            if not isinstance(expected_hash, str) or len(expected_hash) != 64:
                errors.append(f"missing sha256 for runtime file: {rel}")
            elif _sha256(target) != expected_hash.lower():
                errors.append(f"sha256 mismatch for runtime file: {rel}")

    if authorized and status.get("owner_verdict") != "GARDER": errors.append("production authorization requires owner verdict GARDER")
    if authorized and not (source_present and runtime_present): errors.append("production authorization requires complete source and runtime packages")
    if ready and not authorized: errors.append("activation_ready requires production_authorized=true")
    if ready and not (source_present and runtime_present): errors.append("activation_ready requires complete source and runtime packages")
    if require_ready and not ready: errors.append("CIV-1 runtime packaging is not activation-ready")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate fail-closed CIV-1 runtime packaging status")
    parser.add_argument("--require-ready", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    errors = validate(root, require_ready=args.require_ready)
    if errors:
        print("CIV1_RUNTIME_PACKAGING_FAIL")
        for error in errors: print(f"- {error}")
        return 1
    state = _load_status(root)
    print("CIV1_RUNTIME_PACKAGING_OK")
    print(f"activation_ready={str(state.get('activation_ready') is True).lower()}")
    print(f"blocker={state.get('blocker', '')}")
    return 0


if __name__ == "__main__": sys.exit(main())
