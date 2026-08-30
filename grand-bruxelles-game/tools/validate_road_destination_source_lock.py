#!/usr/bin/env python3
"""Fail-close validation for the shipped road-destination source corpus.

This validator proves that the compatible grand-bruxelles-osm-v1 documents present
under data/osm exactly match the committed allowlist and SHA-256 digests. It does not
acquire data and grants no render/runtime/JOUABLE authorization.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
from typing import Any

LOCK_FORMAT = "grand-bruxelles-road-destination-source-lock-v1"
SOURCE_FORMAT = "grand-bruxelles-osm-v1"
DEFAULT_LOCK_NAME = "road_destination_sources.lock.json"


def fail(message: str) -> "NoReturn":
    raise SystemExit(f"ROAD_DESTINATION_SOURCE_LOCK_FAIL: {message}")


def is_sha256(value: Any) -> bool:
    return type(value) is str and len(value) == 64 and all(ch in "0123456789abcdef" for ch in value)


def reject_duplicate_object_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    """Reject ambiguous JSON objects instead of silently accepting last-key-wins parsing."""
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            fail(f"duplicate JSON object key {key!r}")
        result[key] = value
    return result


def canonical_source_path(value: Any) -> str:
    if type(value) is not str or not value or value.strip() != value or "\\" in value:
        fail(f"non-canonical source path {value!r}")
    pure = PurePosixPath(value)
    if pure.is_absolute() or ".." in pure.parts or pure.as_posix() != value:
        fail(f"non-canonical source path {value!r}")
    if not value.startswith("data/osm/") or not value.endswith(".game.json"):
        fail(f"source path outside locked OSM corpus {value!r}")
    return value


def repository_root(source_root: Path) -> Path:
    source_root = source_root.resolve()
    if source_root.name != "osm" or source_root.parent.name != "data":
        fail(f"unexpected source root {source_root}")
    return source_root.parent.parent


def load_lock(source_root: Path, lock_path: Path | None = None) -> dict[str, str]:
    source_root = source_root.resolve()
    repo_root = repository_root(source_root)
    lock_path = (lock_path or (source_root / DEFAULT_LOCK_NAME)).resolve()
    try:
        raw_text = lock_path.read_text(encoding="utf-8")
        payload = json.loads(raw_text, object_pairs_hook=reject_duplicate_object_keys)
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"invalid lock document {lock_path}: {exc}")
    if type(payload) is not dict:
        fail("lock root must be an object")
    expected_fields = {
        "format", "source_format", "source", "license", "evidence_artifact_id",
        "evidence_catalog_sha256", "documents",
    }
    if set(payload) != expected_fields:
        fail("lock field set drift")
    if payload.get("format") != LOCK_FORMAT or payload.get("source_format") != SOURCE_FORMAT:
        fail("lock format drift")
    if payload.get("source") != "OpenStreetMap contributors via Overpass API":
        fail("source attribution drift")
    if payload.get("license") != "ODbL-1.0":
        fail("source license drift")
    if type(payload.get("evidence_artifact_id")) is not int or payload["evidence_artifact_id"] <= 0:
        fail("invalid evidence artifact id")
    if not is_sha256(payload.get("evidence_catalog_sha256")):
        fail("invalid evidence catalog SHA256")
    documents = payload.get("documents")
    if type(documents) is not dict or not documents:
        fail("locked source documents missing")

    locked: dict[str, str] = {}
    for raw_path, raw_digest in documents.items():
        path = canonical_source_path(raw_path)
        if not is_sha256(raw_digest):
            fail(f"invalid locked SHA256 for {path}")
        file_path = (repo_root / path).resolve()
        try:
            file_path.relative_to(source_root)
        except ValueError:
            fail(f"locked source escapes source root {path}")
        if not file_path.is_file():
            fail(f"locked source document missing {path}")
        observed = hashlib.sha256(file_path.read_bytes()).hexdigest()
        if observed != raw_digest:
            fail(f"locked source document SHA256 drift {path}: {observed} != {raw_digest}")
        locked[path] = raw_digest
    return dict(sorted(locked.items()))


def discover_compatible_documents(source_root: Path) -> dict[str, str]:
    source_root = source_root.resolve()
    repo_root = repository_root(source_root)
    compatible: dict[str, str] = {}
    for path in sorted(source_root.rglob("*.game.json")):
        if not path.is_file():
            continue
        try:
            raw = path.read_bytes()
            payload = json.loads(raw.decode("utf-8"))
        except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
            fail(f"invalid source JSON {path}: {exc}")
        if type(payload) is not dict or payload.get("format") != SOURCE_FORMAT:
            continue
        relative = canonical_source_path(path.resolve().relative_to(repo_root).as_posix())
        compatible[relative] = hashlib.sha256(raw).hexdigest()
    return dict(sorted(compatible.items()))


def validate(source_root: Path, lock_path: Path | None = None) -> dict[str, str]:
    locked = load_lock(source_root, lock_path)
    discovered = discover_compatible_documents(source_root)
    if set(discovered) != set(locked):
        unexpected = sorted(set(discovered) - set(locked))
        missing = sorted(set(locked) - set(discovered))
        fail(f"compatible source set drift unexpected={unexpected} missing={missing}")
    for path, digest in locked.items():
        if discovered[path] != digest:
            fail(f"compatible source SHA256 drift {path}: {discovered[path]} != {digest}")
    return locked


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, default=Path(__file__).resolve().parents[1] / "data" / "osm")
    parser.add_argument("--lock", type=Path)
    args = parser.parse_args()
    locked = validate(args.source_root, args.lock)
    print(f"ROAD_DESTINATION_SOURCE_LOCK_OK: documents={len(locked)}")
    for path, digest in locked.items():
        print(f"ROAD_DESTINATION_SOURCE_LOCK_DOCUMENT: {path} sha256={digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
