#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import math
import unicodedata
from pathlib import Path, PurePosixPath

CIV1_PREFIX = "grand-bruxelles-game/assets/characters/civilians/civ1/"
STATUS_PATH = Path("grand-bruxelles-game/assets/characters/civilians/civ1/source_status.json")
SOURCE_ROOT = PurePosixPath("assets/characters/civilians/civ1/source")
REGISTRY_SCHEMA = "grand-bruxelles-civ1-roster-registry-v1"
REQUIRED_READY_FLAGS = ("production_authorized", "activation_ready", "source_package_present")

class DuplicateJSONKeyError(ValueError):
    pass

class NonStandardJSONConstantError(ValueError):
    pass

def _reject_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise DuplicateJSONKeyError(key)
        result[key] = value
    return result

def _reject_nonstandard_constant(token):
    raise NonStandardJSONConstantError(token)

def _parse_finite_float(token: str) -> float:
    value = float(token)
    if not math.isfinite(value):
        raise NonStandardJSONConstantError(token)
    return value

def _load_strict_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=_reject_duplicate_keys, parse_float=_parse_finite_float, parse_constant=_reject_nonstandard_constant)

def _git_blob_sha1(data: bytes) -> str:
    digest = hashlib.sha1()
    digest.update(f"blob {len(data)}\0".encode("ascii"))
    digest.update(data)
    return digest.hexdigest()

def _has_symlink_component(base: Path, parts: tuple[str, ...]) -> bool:
    current = base
    if current.is_symlink():
        return True
    for part in parts:
        current = current / part
        if current.is_symlink():
            return True
    return False

def _canonical_path_text(value: object) -> str | None:
    if not isinstance(value, str) or not value or "\\" in value or "\x00" in value or ":" in value:
        return None
    if value != value.strip() or unicodedata.normalize("NFC", value) != value:
        return None
    if any(unicodedata.category(char) in ("Cc", "Cf", "Zs", "Zl", "Zp") for char in value):
        return None
    pure = PurePosixPath(value)
    if pure.is_absolute() or ".." in pure.parts or pure.as_posix() != value:
        return None
    return value

def _source_file(repo_root: Path, source_path: str) -> Path | None:
    canonical = _canonical_path_text(source_path)
    if canonical is None or canonical.endswith("/"):
        return None
    pure = PurePosixPath(canonical)
    root_parts = SOURCE_ROOT.parts
    if len(pure.parts) <= len(root_parts) or pure.parts[:len(root_parts)] != root_parts or pure.name in ("", ".", ".."):
        return None
    if _has_symlink_component(repo_root, ("grand-bruxelles-game",) + pure.parts):
        return None
    game_root = (repo_root / "grand-bruxelles-game").resolve()
    allowed = (game_root / Path(*root_parts)).resolve()
    candidate = (game_root / Path(*pure.parts)).resolve()
    try:
        candidate.relative_to(allowed)
    except ValueError:
        return None
    return candidate

def _source_manifest_integrity(status: dict, repo_root: Path) -> bool:
    source_paths = status.get("source_paths")
    manifest = status.get("source_manifest")
    if not isinstance(source_paths, list) or not source_paths:
        return False
    if not all(_canonical_path_text(path) is not None and _source_file(repo_root, path) is not None for path in source_paths):
        return False
    if len(set(source_paths)) != len(source_paths):
        return False
    if not isinstance(manifest, dict) or not manifest or set(source_paths) != set(manifest):
        return False
    if not all(_canonical_path_text(path) is not None and _source_file(repo_root, path) is not None for path in manifest):
        return False
    for source_path in source_paths:
        record = manifest.get(source_path)
        if not isinstance(record, dict) or record.get("license_scope_verified") is not True:
            return False
        expected_sha1 = record.get("git_blob_sha1")
        expected_size = record.get("size_bytes")
        if not isinstance(expected_sha1, str) or len(expected_sha1) != 40 or expected_sha1 != expected_sha1.lower() or any(c not in "0123456789abcdef" for c in expected_sha1):
            return False
        if not isinstance(expected_size, int) or isinstance(expected_size, bool) or expected_size < 0:
            return False
        candidate = _source_file(repo_root, source_path)
        if candidate is None or not candidate.is_file():
            return False
        try:
            data = candidate.read_bytes()
        except OSError:
            return False
        if len(data) != expected_size or _git_blob_sha1(data) != expected_sha1:
            return False
    return True

def _status_consistent(status, repo_root: Path) -> bool:
    if not isinstance(status, dict) or status.get("candidate_id") != "CIV-1":
        return False
    if not all(status.get(key) is True for key in REQUIRED_READY_FLAGS):
        return False
    if status.get("blocker") not in (None, ""):
        return False
    character_source = status.get("character_source")
    if not isinstance(character_source, dict):
        return False
    license_evidence = character_source.get("license_evidence")
    if not isinstance(license_evidence, dict):
        return False
    unresolved = license_evidence.get("unresolved_components")
    if not isinstance(unresolved, list) or unresolved:
        return False
    return _source_manifest_integrity(status, repo_root)

def source_ready(repo_root: Path) -> bool:
    if _has_symlink_component(repo_root, tuple(STATUS_PATH.parts)):
        return False
    try:
        status = _load_strict_json(repo_root / STATUS_PATH)
    except (OSError, json.JSONDecodeError, DuplicateJSONKeyError, NonStandardJSONConstantError):
        return False
    return _status_consistent(status, repo_root)

def _canonical_asset_path(value: object) -> str | None:
    canonical = _canonical_path_text(value)
    if canonical is None:
        return None
    pure = PurePosixPath(canonical)
    if len(pure.parts) < 2 or canonical.endswith("/") or pure.name in ("", ".", ".."):
        return None
    return canonical

def registry_consistent(registry) -> bool:
    if not isinstance(registry, dict) or registry.get("schema") != REGISTRY_SCHEMA:
        return False
    entries = registry.get("entries")
    if not isinstance(entries, list):
        return False
    identities = []
    for entry in entries:
        if not isinstance(entry, dict):
            return False
        asset_path = _canonical_asset_path(entry.get("asset_path"))
        if asset_path is None:
            return False
        identities.append(asset_path)
    return len(identities) == len(set(identities))

def blocking_entries(registry, repo_root: Path) -> list[str]:
    if not registry_consistent(registry):
        raise ValueError("invalid CIV-1 roster registry structure")
    if source_ready(repo_root):
        return []
    return [entry["asset_path"] for entry in registry["entries"] if entry["asset_path"].startswith(CIV1_PREFIX)]

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("registry", type=Path)
    parser.add_argument("--repo-root", type=Path, default=Path("."))
    args=parser.parse_args()
    try:
        registry = _load_strict_json(args.registry)
        blocked = blocking_entries(registry, args.repo_root)
    except (OSError, json.JSONDecodeError, DuplicateJSONKeyError, NonStandardJSONConstantError, ValueError) as exc:
        print(f"CIV1_ROSTER_SOURCE_READINESS_ERROR {exc}")
        return 2
    if blocked:
        print("CIV1_ROSTER_SOURCE_NOT_READY " + json.dumps(sorted(set(blocked))))
        return 2
    print("CIV1_ROSTER_SOURCE_READINESS_GREEN")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
