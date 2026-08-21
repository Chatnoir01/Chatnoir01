#!/usr/bin/env python3
from __future__ import annotations

import copy
import hashlib
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


def git_blob_sha1(data: bytes) -> str:
    digest = hashlib.sha1()
    digest.update(f"blob {len(data)}\0".encode("ascii"))
    digest.update(data)
    return digest.hexdigest()


def install_fake_sources(root: Path, status: dict) -> dict:
    pins: dict = {}
    for index, rel in enumerate(status["source_paths"]):
        data = f"source-{index}".encode("utf-8")
        target = root / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        pins[rel] = {
            "upstream_path": status["source_manifest"][rel]["upstream_path"],
            "git_blob_sha1": git_blob_sha1(data),
            "size_bytes": len(data),
        }
    status["source_manifest"] = copy.deepcopy(pins)
    return pins


def test_current_blocked_state_is_truthful() -> None:
    errors = module.validate(ROOT)
    assert not errors, errors
    errors = module.validate(ROOT, require_ready=True)
    assert "CIV-1 runtime packaging is not activation-ready" in errors


def test_player_reuse_cannot_be_runtime_package() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        status = copy.deepcopy(BASE)
        status["runtime_scene"] = "assets/characters/player_character.glb"
        status["runtime_files"] = ["assets/characters/player_character.glb"]
        write_status(root, status)
        errors = module.validate(root)
        assert any("canonical CIV-1 directory" in error or "player character reuse" in error for error in errors), errors


def test_authorization_cannot_precede_package() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        status = copy.deepcopy(BASE)
        status["production_authorized"] = True
        write_status(root, status)
        errors = module.validate(root)
        assert "production authorization requires complete source and runtime packages" in errors


def test_declared_runtime_requires_hash_and_file() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        status = copy.deepcopy(BASE)
        status["runtime_package_present"] = True
        write_status(root, status)
        errors = module.validate(root)
        assert any("declared runtime file missing" in error for error in errors), errors


def test_source_manifest_pin_drift_is_rejected() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        status = copy.deepcopy(BASE)
        first = status["source_paths"][0]
        status["source_manifest"][first]["git_blob_sha1"] = "0" * 40
        write_status(root, status)
        errors = module.validate(root)
        assert any("source manifest pin drift" in error for error in errors), errors


def test_declared_source_bytes_must_match_pinned_git_blobs() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        status = copy.deepcopy(BASE)
        for rel in status["source_paths"]:
            target = root / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(b"not-the-pinned-upstream-bytes")
        status["source_package_present"] = True
        write_status(root, status)
        errors = module.validate(root)
        assert any("source git blob mismatch" in error or "source size mismatch" in error for error in errors), errors


def test_ready_package_accepts_verified_canonical_scene() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        status = copy.deepcopy(BASE)
        original_pins = module.EXPECTED_SOURCE_MANIFEST
        fake_pins = install_fake_sources(root, status)
        module.EXPECTED_SOURCE_MANIFEST = copy.deepcopy(fake_pins)
        try:
            scene = root / status["runtime_scene"]
            scene.parent.mkdir(parents=True, exist_ok=True)
            scene.write_text("[gd_scene format=3]\n", encoding="utf-8")
            digest = hashlib.sha256(scene.read_bytes()).hexdigest()
            status["source_package_present"] = True
            status["runtime_package_present"] = True
            status["production_authorized"] = True
            status["activation_ready"] = True
            status["runtime_sha256"] = {status["runtime_scene"]: digest}
            status["blocker"] = ""
            write_status(root, status)
            errors = module.validate(root, require_ready=True)
            assert not errors, errors
        finally:
            module.EXPECTED_SOURCE_MANIFEST = original_pins


def test_hash_mismatch_is_rejected() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        status = copy.deepcopy(BASE)
        original_pins = module.EXPECTED_SOURCE_MANIFEST
        fake_pins = install_fake_sources(root, status)
        module.EXPECTED_SOURCE_MANIFEST = copy.deepcopy(fake_pins)
        try:
            scene = root / status["runtime_scene"]
            scene.parent.mkdir(parents=True, exist_ok=True)
            scene.write_text("[gd_scene format=3]\n", encoding="utf-8")
            status["source_package_present"] = True
            status["runtime_package_present"] = True
            status["production_authorized"] = True
            status["activation_ready"] = True
            status["runtime_sha256"] = {status["runtime_scene"]: "0" * 64}
            write_status(root, status)
            errors = module.validate(root, require_ready=True)
            assert any("sha256 mismatch" in error for error in errors), errors
        finally:
            module.EXPECTED_SOURCE_MANIFEST = original_pins


def main() -> int:
    tests = [
        test_current_blocked_state_is_truthful,
        test_player_reuse_cannot_be_runtime_package,
        test_authorization_cannot_precede_package,
        test_declared_runtime_requires_hash_and_file,
        test_source_manifest_pin_drift_is_rejected,
        test_declared_source_bytes_must_match_pinned_git_blobs,
        test_ready_package_accepts_verified_canonical_scene,
        test_hash_mismatch_is_rejected,
    ]
    for test in tests:
        test()
        print(f"PASS {test.__name__}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
