#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath

CIV1_PREFIX = "grand-bruxelles-game/assets/characters/civilians/civ1/"
STATUS_PATH = Path("grand-bruxelles-game/assets/characters/civilians/civ1/source_status.json")
SOURCE_ROOT = PurePosixPath("assets/characters/civilians/civ1/source")
REQUIRED_READY_FLAGS = (
    "production_authorized",
    "activation_ready",
    "source_package_present",
)


def _git_blob_sha1(data: bytes) -> str:
    digest = hashlib.sha1()
    digest.update(f"blob {len(data)}\0".encode("ascii"))
    digest.update(data)
    return digest.hexdigest()


def _has_symlink_component(base: Path, parts: tuple[str, ...]) -> bool:
    """Treat every canonical Character path component as identity, not a locator."""
    current = base
    if current.is_symlink():
        return True
    for part in parts:
        current = current / part
        if current.is_symlink():
            return True
    return False


def _source_file(repo_root: Path, source_path: str) -> Path | None:
    if not isinstance(source_path, str) or not source_path:
        return None
    if "\\" in source_path:
        return None
    pure = PurePosixPath(source_path)
    if pure.is_absolute() or pure.as_posix() != source_path or ".." in pure.parts:
        return None
    root_parts = SOURCE_ROOT.parts
    if len(pure.parts) <= len(root_parts) or pure.parts[: len(root_parts)] != root_parts:
        return None

    # A manifest path is an identity, not merely a locator to matching bytes.
    # Reject aliases in every lexical component from the repository root through
    # the declared file, including ancestor-directory symlinks and in-root file
    # aliases whose resolved target would otherwise pass the byte checks below.
    lexical_parts = ("grand-bruxelles-game",) + pure.parts
    if _has_symlink_component(repo_root, lexical_parts):
        return None

    game_root = (repo_root / "grand-bruxelles-game").resolve()
    lexical_root = game_root / Path(*root_parts)
    lexical_candidate = game_root / Path(*pure.parts)
    allowed = lexical_root.resolve()
    candidate = lexical_candidate.resolve()
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
    if not all(isinstance(path, str) and path for path in source_paths):
        return False
    if len(set(source_paths)) != len(source_paths):
        return False
    if not isinstance(manifest, dict) or not manifest:
        return False
    if set(source_paths) != set(manifest):
        return False

    for source_path in source_paths:
        record = manifest.get(source_path)
        if not isinstance(record, dict) or record.get("license_scope_verified") is not True:
            return False
        expected_sha1 = record.get("git_blob_sha1")
        expected_size = record.get("size_bytes")
        if (
            not isinstance(expected_sha1, str)
            or len(expected_sha1) != 40
            or expected_sha1 != expected_sha1.lower()
            or any(c not in "0123456789abcdef" for c in expected_sha1)
        ):
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


def _status_consistent(status: object, repo_root: Path) -> bool:
    if not isinstance(status, dict):
        return False
    if status.get("candidate_id") != "CIV-1":
        return False
    if not all(status.get(key) is True for key in REQUIRED_READY_FLAGS):
        return False

    blocker = status.get("blocker")
    if blocker not in (None, ""):
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
    # source_status.json is the canonical authorization record. Reading through a
    # symlink would let another file impersonate that identity, so fail closed
    # before parsing even when the target contains otherwise valid JSON.
    if _has_symlink_component(repo_root, tuple(STATUS_PATH.parts)):
        return False
    status_path = repo_root / STATUS_PATH
    try:
        status = json.loads(status_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return False
    return _status_consistent(status, repo_root)


def blocking_entries(registry: object, repo_root: Path) -> list[str]:
    if source_ready(repo_root):
        return []
    if not isinstance(registry, dict) or not isinstance(registry.get("entries"), list):
        return []
    blocked = []
    for entry in registry["entries"]:
        if not isinstance(entry, dict):
            continue
        asset_path = entry.get("asset_path")
        if isinstance(asset_path, str) and asset_path.startswith(CIV1_PREFIX):
            blocked.append(asset_path)
    return blocked


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("registry", type=Path)
    parser.add_argument("--repo-root", type=Path, default=Path("."))
    args = parser.parse_args()
    try:
        registry = json.loads(args.registry.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"CIV1_ROSTER_SOURCE_READINESS_ERROR {exc}")
        return 2
    blocked = blocking_entries(registry, args.repo_root)
    if blocked:
        print("CIV1_ROSTER_SOURCE_NOT_READY " + json.dumps(sorted(set(blocked))))
        return 2
    print("CIV1_ROSTER_SOURCE_READINESS_GREEN")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
