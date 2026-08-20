#!/usr/bin/env python3
"""Fail-closed verifier for Grand Bruxelles intake artifacts.

This tool validates local/downloaded payload integrity before any normalizer is allowed to run.
Artifact integrity is distinct from reuse permission: unresolved licence terms stay visible and
never imply runtime or production authorization.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any

HASH_RE = re.compile(r"^[0-9a-fA-F]{64}$")
CRS_RE = re.compile(r"EPSG:\s*\d+", re.I)


def walk(value: Any):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)


def recursive_values(value: Any, keys: set[str]) -> list[Any]:
    found: list[Any] = []
    for item in walk(value):
        for key, child in item.items():
            if str(key).lower() in keys:
                found.append(child)
    return found


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def file_records(manifest: Any) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for item in walk(manifest):
        filename = item.get("file") or item.get("path") or item.get("filename")
        expected = item.get("sha256") or item.get("sha_256")
        if isinstance(filename, str) and isinstance(expected, str) and HASH_RE.fullmatch(expected.strip()):
            records.append({"file": filename, "sha256": expected.lower(), "bytes": item.get("bytes") or item.get("size")})
    unique: dict[tuple[str, str], dict[str, Any]] = {}
    for record in records:
        unique[(record["file"], record["sha256"])] = record
    return [unique[key] for key in sorted(unique)]


def is_authorized_true(manifest: Any, key: str) -> bool:
    for item in walk(manifest):
        if item.get(key) is True:
            return True
    return False


def reuse_terms_resolved(licenses: list[str]) -> bool:
    unresolved_markers = ("UNRESOLVED", "UNKNOWN", "UNVERIFIED", "TO_BE_VERIFIED")
    return not any(any(marker in value.upper() for marker in unresolved_markers) for value in licenses)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--require-crs", action="store_true")
    parser.add_argument("--minimum-files", type=int, default=1)
    parser.add_argument("--summary", type=Path)
    args = parser.parse_args()

    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    if is_authorized_true(manifest, "runtime_authorized"):
        raise SystemExit("artifact gate failed: intake manifest must not grant runtime authorization")
    if is_authorized_true(manifest, "production_authorized"):
        raise SystemExit("artifact gate failed: intake manifest must not grant production authorization")

    licenses = [str(v).strip() for v in recursive_values(manifest, {"license", "licence"}) if str(v).strip()]
    if not licenses:
        raise SystemExit("artifact gate failed: no license/licence metadata found")

    records = file_records(manifest)
    if len(records) < args.minimum_files:
        raise SystemExit(f"artifact gate failed: only {len(records)} hashed file records, need {args.minimum_files}")

    verified: list[dict[str, Any]] = []
    root = args.root.resolve()
    for record in records:
        candidate = (args.root / record["file"]).resolve()
        try:
            candidate.relative_to(root)
        except ValueError as exc:
            raise SystemExit(f"artifact gate failed: path escapes artifact root: {record['file']}") from exc
        if not candidate.is_file():
            raise SystemExit(f"artifact gate failed: missing file {record['file']}")
        size = candidate.stat().st_size
        if size <= 0:
            raise SystemExit(f"artifact gate failed: empty file {record['file']}")
        if record.get("bytes") not in (None, ""):
            try:
                expected_size = int(record["bytes"])
            except (TypeError, ValueError):
                expected_size = None
            if expected_size is not None and expected_size != size:
                raise SystemExit(f"artifact gate failed: size mismatch for {record['file']}: {size} != {expected_size}")
        actual = sha256_file(candidate)
        if actual != record["sha256"]:
            raise SystemExit(f"artifact gate failed: sha256 mismatch for {record['file']}")
        verified.append({"file": record["file"], "bytes": size, "sha256": actual})

    if args.require_crs:
        text = json.dumps(manifest, ensure_ascii=False)
        if not CRS_RE.search(text):
            raise SystemExit("artifact gate failed: geospatial artifact has no explicit EPSG CRS metadata")

    terms_resolved = reuse_terms_resolved(licenses)
    summary = {
        "schema": "grand-bruxelles-intake-artifact-verification-v2",
        "manifest": args.manifest.name,
        "verified_file_count": len(verified),
        "licenses": sorted(set(licenses)),
        "reuse_terms_resolved": terms_resolved,
        "files": verified,
        "runtime_authorized": False,
        "production_authorized": False,
        "result": "ARTIFACT_VERIFIED",
        "production_gate": "TERMS_OK" if terms_resolved else "TERMS_BLOCKED",
    }
    if args.summary:
        args.summary.parent.mkdir(parents=True, exist_ok=True)
        args.summary.write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"INTAKE_ARTIFACT_VERIFIED: {len(verified)} files terms={'resolved' if terms_resolved else 'blocked'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
