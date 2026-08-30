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
    errors = module.validate(ROOT)
    assert not errors, errors
    errors = module.validate(ROOT, require_ready=True)
    assert "CIV-1 runtime packaging is not activation-ready" in errors


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


def test_unresolved_license_scope_blocks_source_materialization() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp); status = copy.deepcopy(BASE); status["source_package_present"] = True
        for rel in status["source_paths"]:
            target = root / rel; target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(b"placeholder")
        write_status(root, status)
        errors = module.validate(root)
        assert "source materialization requires verified license scope for every source blob" in errors
        assert "source materialization forbidden while character license evidence remains unresolved" in errors


def test_repo_level_cc0_regression_is_rejected() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp); status = copy.deepcopy(BASE)
        status["character_source"] = {"repository": module.EXPECTED["character_repo"], "commit": module.EXPECTED["character_commit"], "license": "CC0-1.0"}
        write_status(root, status)
        errors = module.validate(root)
        assert "character source license claim must remain MIXED" in errors
        assert "character source license evidence missing" in errors


def test_source_manifest_license_scope_drift_is_rejected() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp); status = copy.deepcopy(BASE)
        first = status["source_paths"][0]
        status["source_manifest"][first]["license_scope_verified"] = True
        status["source_manifest"][first]["license"] = "CC0-1.0"
        write_status(root, status)
        errors = module.validate(root)
        assert any("source manifest pin drift" in e or "source manifest metadata drift" in e for e in errors), errors


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
        test_unresolved_license_scope_blocks_source_materialization,
        test_repo_level_cc0_regression_is_rejected,
        test_source_manifest_license_scope_drift_is_rejected,
        test_declared_runtime_requires_hash_and_file,
    ]
    for test in tests:
        test(); print(f"PASS {test.__name__}")
    return 0


if __name__ == "__main__": raise SystemExit(main())
