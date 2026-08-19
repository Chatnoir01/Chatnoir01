#!/usr/bin/env python3
"""Run the existing C01 source materializer against a pre-downloaded locked package.

Network I/O is intentionally removed from the materializer path. The package must
match the exact source URL and SHA-256 pinned in the locked C01 source summary.
All geometry/ID/canonical-payload checks remain delegated to the production
materializer unchanged.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
from typing import Any


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot import {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def run(
    repo_root: Path,
    selection_path: Path,
    summary_path: Path,
    contract_path: Path,
    distribution_key: str,
    package_path: Path,
    output_root: Path,
) -> dict[str, Any]:
    summary = json.loads(summary_path.read_text(encoding="utf-8"))
    locked = summary.get("source_shards", {}).get(distribution_key)
    if not isinstance(locked, dict):
        raise RuntimeError(f"distribution missing from locked summary: {distribution_key}")
    source = locked.get("source", {})
    expected_url = str(source.get("distribution_url", ""))
    expected_sha = str(source.get("package_sha256", "")).lower()
    if not expected_url.startswith("https://urbisdownload.datastore.brussels/"):
        raise RuntimeError("locked source URL is not official UrbIS HTTPS")
    if len(expected_sha) != 64:
        raise RuntimeError("locked source package SHA-256 is invalid")

    package = package_path.read_bytes()
    actual_sha = sha256_bytes(package)
    if actual_sha != expected_sha:
        raise RuntimeError(f"cached package SHA-256 drift: {actual_sha} != {expected_sha}")

    materializer = load_module(
        "region_lod2_source_materializer",
        repo_root / "grand-bruxelles-game/tools/qa/materialize_region_lod2_source_shard.py",
    )
    original_load_module = materializer.load_module

    def patched_load_module(name: str, path: Path):
        module = original_load_module(name, path)
        if name == "urbis_batch_verifier":
            original_http_get = module.http_get

            def cached_http_get(url: str, *args, **kwargs) -> bytes:
                if url != expected_url:
                    raise RuntimeError(
                        f"materializer requested unexpected source URL: {url!r} != {expected_url!r}"
                    )
                print(
                    "URBIS_LOCKED_PACKAGE_CACHE_HIT: "
                    f"bytes={len(package)} sha256={actual_sha}",
                    flush=True,
                )
                return package

            module.http_get = cached_http_get
            module._original_http_get_for_audit = original_http_get
        return module

    materializer.load_module = patched_load_module
    result = materializer.run(
        repo_root,
        selection_path,
        summary_path,
        contract_path,
        distribution_key,
        output_root,
    )
    report_sha = sha256_bytes(
        (output_root / str(result["tile"]) / "report.json").read_bytes()
    )
    print(
        "REGION_LOD2_C01_CACHED_SHARD_OK: "
        f"tile={result['tile']} package_sha256={actual_sha} report_sha256={report_sha}",
        flush=True,
    )
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, default=Path("."))
    parser.add_argument("--selection", type=Path, required=True)
    parser.add_argument("--summary", type=Path, required=True)
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--distribution-key", required=True)
    parser.add_argument("--package", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    args = parser.parse_args()
    try:
        run(
            args.repo_root.resolve(),
            args.selection.resolve(),
            args.summary.resolve(),
            args.contract.resolve(),
            args.distribution_key,
            args.package.resolve(),
            args.output_root.resolve(),
        )
    except Exception as exc:
        print(f"REGION_LOD2_C01_CACHED_SHARD_ERROR: {exc}", flush=True)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
