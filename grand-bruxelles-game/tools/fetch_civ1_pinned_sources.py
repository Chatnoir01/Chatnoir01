#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import urllib.parse
import urllib.request
from pathlib import Path

CHARACTER_PREFIX = "assets/characters/civilians/civ1/source/"


def git_blob_sha1(path: Path) -> str:
    size = path.stat().st_size
    digest = hashlib.sha1()
    digest.update(f"blob {size}\0".encode("ascii"))
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def repo_slug(repository: str) -> str:
    parsed = urllib.parse.urlparse(repository)
    if parsed.scheme != "https" or parsed.netloc != "github.com":
        raise ValueError(f"only pinned https://github.com sources are supported: {repository}")
    slug = parsed.path.strip("/")
    if slug.endswith(".git"):
        slug = slug[:-4]
    parts = slug.split("/")
    if len(parts) != 2 or not all(parts):
        raise ValueError(f"invalid GitHub repository URL: {repository}")
    return slug


def raw_url(repository: str, commit: str, upstream_path: str) -> str:
    if len(commit) != 40 or any(ch not in "0123456789abcdef" for ch in commit.lower()):
        raise ValueError("source commit must be an exact 40-hex SHA")
    if upstream_path.startswith("/") or ".." in Path(upstream_path).parts:
        raise ValueError(f"unsafe upstream path: {upstream_path}")
    quoted = "/".join(urllib.parse.quote(part, safe="") for part in upstream_path.split("/"))
    return f"https://raw.githubusercontent.com/{repo_slug(repository)}/{commit}/{quoted}"


def load_plan(root: Path) -> list[dict]:
    status_path = root / "assets/characters/civilians/civ1/source_status.json"
    status = json.loads(status_path.read_text(encoding="utf-8"))
    manifest = status.get("source_manifest")
    source_paths = status.get("source_paths")
    if not isinstance(manifest, dict) or not isinstance(source_paths, list):
        raise ValueError("CIV-1 source manifest is missing")
    if set(manifest) != set(source_paths):
        raise ValueError("CIV-1 source manifest/path set mismatch")

    character = status["character_source"]
    footwear = status["footwear_source"]
    plan: list[dict] = []
    for rel in source_paths:
        pin = manifest.get(rel)
        if not isinstance(pin, dict):
            raise ValueError(f"source manifest entry missing: {rel}")
        if not rel.startswith(CHARACTER_PREFIX):
            raise ValueError(f"source destination escapes canonical CIV-1 source directory: {rel}")
        if rel.endswith("shoes03.obj"):
            repository = footwear["repository"]
            commit = footwear["commit"]
        else:
            repository = character["repository"]
            commit = character["commit"]
        plan.append(
            {
                "relative_path": rel,
                "url": raw_url(repository, commit, pin["upstream_path"]),
                "git_blob_sha1": pin["git_blob_sha1"],
                "size_bytes": pin.get("size_bytes"),
            }
        )
    return plan


def select_plan(plan: list[dict], requested_paths: list[str] | None) -> list[dict]:
    if not requested_paths:
        return plan
    requested = list(dict.fromkeys(requested_paths))
    available = {item["relative_path"]: item for item in plan}
    unknown = [path for path in requested if path not in available]
    if unknown:
        raise ValueError(f"requested CIV-1 source is not pinned: {', '.join(unknown)}")
    return [available[path] for path in requested]


def verify_file(path: Path, expected_blob: str, expected_size: int | None) -> None:
    if expected_size is not None and path.stat().st_size != expected_size:
        raise ValueError(f"source size mismatch for {path}: expected {expected_size}, got {path.stat().st_size}")
    actual_blob = git_blob_sha1(path)
    if actual_blob != expected_blob:
        raise ValueError(f"source git blob mismatch for {path}: expected {expected_blob}, got {actual_blob}")


def fetch_one(root: Path, item: dict) -> str:
    target = root / item["relative_path"]
    target.parent.mkdir(parents=True, exist_ok=True)
    expected_size = item.get("size_bytes")
    if target.is_file():
        verify_file(target, item["git_blob_sha1"], expected_size)
        return "already_verified"

    tmp = target.with_name(target.name + ".part")
    if tmp.exists():
        tmp.unlink()
    try:
        request = urllib.request.Request(item["url"], headers={"User-Agent": "Grand-Bruxelles-CIV1-Pinned-Source-Fetcher/1"})
        with urllib.request.urlopen(request, timeout=120) as response, tmp.open("wb") as output:
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                output.write(chunk)
        verify_file(tmp, item["git_blob_sha1"], expected_size)
        os.replace(tmp, target)
    finally:
        if tmp.exists():
            tmp.unlink()
    return "fetched_verified"


def main() -> int:
    parser = argparse.ArgumentParser(description="Plan or fetch the exact pinned CC0 source bytes for CIV-1")
    parser.add_argument("--fetch", action="store_true", help="perform network downloads; without this flag only print the immutable plan")
    parser.add_argument(
        "--only",
        action="append",
        default=[],
        metavar="RELATIVE_PATH",
        help="operate only on an exact pinned CIV-1 relative path; may be repeated",
    )
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    try:
        plan = select_plan(load_plan(root), args.only)
        for item in plan:
            if args.fetch:
                state = fetch_one(root, item)
                print(f"{state} {item['relative_path']} {item['git_blob_sha1']}")
            else:
                print(f"PLAN {item['relative_path']} {item['git_blob_sha1']} {item['url']}")
        print(f"CIV1_PINNED_SOURCE_PLAN_OK files={len(plan)} network_fetch={str(args.fetch).lower()}")
        return 0
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as exc:
        print(f"CIV1_PINNED_SOURCE_PLAN_FAIL: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
