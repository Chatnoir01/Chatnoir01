#!/usr/bin/env python3
from __future__ import annotations

import copy
import importlib.util
import json
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tools/validate_civ1_runtime_packaging.py"
spec = importlib.util.spec_from_file_location("civ1_packaging", MODULE_PATH)
module = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(module)
STATUS_PATH = ROOT / "assets/characters/civilians/civ1/source_status.json"
BASE = json.loads(STATUS_PATH.read_text(encoding="utf-8"))


def write_status(root: Path, status: dict) -> None:
    path = root / "assets/characters/civilians/civ1/source_status.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(status, indent=2) + "\n", encoding="utf-8")


def test_current_blocked_state_is_truthful() -> None:
    assert not module.validate(ROOT)
    assert "CIV-1 runtime packaging is not activation-ready" in module.validate(ROOT, require_ready=True)


def test_player_reuse_cannot_be_runtime_package() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp); status = copy.deepcopy(BASE)
        status["runtime_scene"] = "assets/characters/player_character.glb"
        status["runtime_files"] = ["assets/characters/player_character.glb"]
        write_status(root, status)
        errors = module.validate(root)
        assert any("canonical CIV-1 directory" in e or "player character reuse" in e for e in errors), errors


def test_authorization_cannot_precede_package() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp); status = copy.deepcopy(BASE); status["production_authorized"] = True
        write_status(root, status)
        assert "production authorization requires complete source and runtime packages" in module.validate(root)


def test_embedded_mixamo_payload_blocks_source_materialization() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp); status = copy.deepcopy(BASE); status["source_package_present"] = True
        for rel in status["source_paths"]:
            target = root / rel; target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(b"placeholder")
        write_status(root, status)
        errors = module.validate(root)
        assert "source materialization requires verified license scope for every source blob" in errors
        assert "source materialization forbidden while character license components remain unresolved" in errors


def test_repo_level_cc0_regression_is_rejected() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp); status = copy.deepcopy(BASE)
        status["character_source"] = {"repository": module.EXPECTED["character_repo"], "commit": module.EXPECTED["character_commit"], "license": "CC0-1.0"}
        write_status(root, status)
        errors = module.validate(root)
        assert "character source license claim must remain MIXED_BY_COMPONENT" in errors
        assert "character source license evidence missing" in errors


def test_readme_and_notice_evidence_drift_is_rejected() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp); status = copy.deepcopy(BASE)
        status["character_source"]["license_evidence"]["readme_git_blob_sha1"] = "0" * 40
        write_status(root, status)
        assert "character source license evidence drift: readme_git_blob_sha1" in module.validate(root)


def test_canonical_rigged_hair_pin_is_required() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp); status = copy.deepcopy(BASE)
        hair = "assets/characters/civilians/civ1/source/vitruvian_hair_rigged.glb"
        status["source_manifest"][hair]["git_blob_sha1"] = "0" * 40
        write_status(root, status)
        assert f"source manifest pin drift: {hair}" in module.validate(root)


def test_obsolete_hair_intermediate_cannot_reenter_manifest() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp); status = copy.deepcopy(BASE)
        status["excluded_upstream_intermediates"] = ["godot_project/vitruvian_hair.glb"]
        write_status(root, status)
        assert "excluded upstream hair intermediates drift" in module.validate(root)


def test_declared_runtime_requires_hash_and_file() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp); status = copy.deepcopy(BASE); status["runtime_package_present"] = True
        write_status(root, status)
        assert any("declared runtime file missing" in e for e in module.validate(root))


def main() -> int:
    tests = [
        test_current_blocked_state_is_truthful,
        test_player_reuse_cannot_be_runtime_package,
        test_authorization_cannot_precede_package,
        test_embedded_mixamo_payload_blocks_source_materialization,
        test_repo_level_cc0_regression_is_rejected,
        test_readme_and_notice_evidence_drift_is_rejected,
        test_canonical_rigged_hair_pin_is_required,
        test_obsolete_hair_intermediate_cannot_reenter_manifest,
        test_declared_runtime_requires_hash_and_file,
    ]
    for test in tests:
        test(); print(f"PASS {test.__name__}")
    return 0


if __name__ == "__main__": raise SystemExit(main())
