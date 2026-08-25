#!/usr/bin/env python3
"""Snapshot every public City of Brussels Open Data dataset as source-only evidence.

The tool discovers the catalogue once through Explore API v2.1, then downloads the
complete JSON export for every dataset with records. It supports deterministic
sharding for GitHub Actions. Nothing produced here authorizes runtime/game use.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

API_BASE = "https://opendata.brussels.be/api/explore/v2.1"
USER_AGENT = "Grand-Bruxelles-Game-OpenData-Snapshot/1.0"


def _request(url: str, retries: int = 7):
    last: Exception | None = None
    for attempt in range(max(1, retries)):
        req = urllib.request.Request(
            url,
            headers={"User-Agent": USER_AGENT, "Accept": "application/json", "Accept-Encoding": "identity"},
        )
        try:
            return urllib.request.urlopen(req, timeout=180)
        except urllib.error.HTTPError as exc:
            last = exc
            retryable = exc.code == 429 or 500 <= exc.code < 600
            if not retryable or attempt + 1 >= retries:
                raise
            retry_after = exc.headers.get("Retry-After")
            wait = float(retry_after) if retry_after and retry_after.isdigit() else min(60.0, float(2**attempt))
            print(f"RETRY_HTTP code={exc.code} wait={wait} url={url}", file=sys.stderr)
            time.sleep(wait)
        except Exception as exc:
            last = exc
            if attempt + 1 >= retries:
                raise
            wait = min(60.0, float(2**attempt))
            print(f"RETRY_ERROR error={exc!r} wait={wait} url={url}", file=sys.stderr)
            time.sleep(wait)
    raise RuntimeError(f"request failed: {url}: {last}")


def _get_json(url: str, retries: int = 7) -> Any:
    with _request(url, retries=retries) as response:
        return json.loads(response.read().decode("utf-8"))


def discover_catalog(retries: int = 7) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    offset = 0
    while True:
        payload = _get_json(f"{API_BASE}/catalog/datasets?limit=100&offset={offset}", retries=retries)
        page = payload.get("results")
        if not isinstance(page, list):
            raise RuntimeError("catalog response has no results list")
        rows.extend(page)
        total = int(payload.get("total_count", len(rows)))
        print(f"CATALOG_PROGRESS rows={len(rows)} total={total}")
        if not page or len(rows) >= total:
            break
        offset += len(page)

    by_id: dict[str, dict[str, Any]] = {}
    for row in rows:
        dataset_id = row.get("dataset_id")
        if not isinstance(dataset_id, str) or not dataset_id:
            raise RuntimeError("catalog contains a dataset without dataset_id")
        if dataset_id in by_id:
            raise RuntimeError(f"duplicate dataset_id: {dataset_id}")
        by_id[dataset_id] = row
    return [by_id[key] for key in sorted(by_id)]


def safe_id(dataset_id: str) -> str:
    value = re.sub(r"[^A-Za-z0-9._-]+", "_", dataset_id).strip("._")
    return value or hashlib.sha256(dataset_id.encode("utf-8")).hexdigest()


def shard_rows(rows: list[dict[str, Any]], shard_index: int, shard_count: int) -> list[dict[str, Any]]:
    if shard_count < 1 or not (0 <= shard_index < shard_count):
        raise ValueError("invalid shard index/count")
    ordered = sorted(rows, key=lambda row: str(row["dataset_id"]))
    return [row for index, row in enumerate(ordered) if index % shard_count == shard_index]


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _dataset_meta(row: dict[str, Any]) -> dict[str, Any]:
    metas = row.get("metas") if isinstance(row.get("metas"), dict) else {}
    default = metas.get("default") if isinstance(metas.get("default"), dict) else {}
    return {
        "dataset_id": row["dataset_id"],
        "title": default.get("title"),
        "license": default.get("license"),
        "records_count_catalog": default.get("records_count"),
        "has_records": bool(row.get("has_records")),
    }


def download_export(dataset_id: str, output: Path, retries: int = 7) -> tuple[str, int]:
    quoted = urllib.parse.quote(dataset_id, safe="")
    url = f"{API_BASE}/catalog/datasets/{quoted}/exports/json?timezone=UTC&use_labels=false"
    output.parent.mkdir(parents=True, exist_ok=True)
    partial = output.with_suffix(output.suffix + ".part")
    partial.unlink(missing_ok=True)
    digest = hashlib.sha256()
    size = 0
    try:
        with _request(url, retries=retries) as response, partial.open("wb") as handle:
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                handle.write(chunk)
                digest.update(chunk)
                size += len(chunk)
        if size == 0:
            raise RuntimeError(f"empty export for {dataset_id}")
        os.replace(partial, output)
        return digest.hexdigest(), size
    finally:
        partial.unlink(missing_ok=True)


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def command_catalog(args: argparse.Namespace) -> int:
    rows = discover_catalog(args.retries)
    out = Path(args.output)
    write_json(out, rows)
    digest = sha256_file(out)
    Path(str(out) + ".sha256").write_text(f"{digest}  {out.name}\n", encoding="utf-8")
    print(f"CITY_OPEN_DATA_CATALOG_OK datasets={len(rows)} sha256={digest}")
    return 0


def command_shard(args: argparse.Namespace) -> int:
    catalog_path = Path(args.catalog)
    rows = json.loads(catalog_path.read_text(encoding="utf-8"))
    if not isinstance(rows, list):
        raise RuntimeError("catalog file must contain a list")
    selected = shard_rows(rows, args.shard_index, args.shard_count)
    root = Path(args.output)
    data_dir = root / "datasets"
    meta_dir = root / "metadata"
    failures: list[dict[str, str]] = []
    entries: list[dict[str, Any]] = []

    for number, row in enumerate(selected, 1):
        dataset_id = str(row["dataset_id"])
        token = safe_id(dataset_id)
        write_json(meta_dir / f"{token}.json", row)
        entry = _dataset_meta(row)
        entry["metadata_file"] = f"metadata/{token}.json"
        print(f"SHARD_DATASET shard={args.shard_index} item={number}/{len(selected)} id={dataset_id}")
        if not row.get("has_records"):
            entry["status"] = "metadata_only_no_records"
            entries.append(entry)
            continue
        try:
            path = data_dir / f"{token}.json"
            digest, size = download_export(dataset_id, path, retries=args.retries)
            Path(str(path) + ".sha256").write_text(f"{digest}  {path.name}\n", encoding="utf-8")
            entry.update({"status": "downloaded", "file": f"datasets/{token}.json", "sha256": digest, "bytes": size})
        except Exception as exc:
            entry.update({"status": "failed", "error": str(exc)})
            failures.append({"dataset_id": dataset_id, "error": str(exc)})
            print(f"SHARD_FAILURE id={dataset_id} error={exc!r}", file=sys.stderr)
        entries.append(entry)
        if args.delay > 0:
            time.sleep(args.delay)

    manifest = {
        "schema": "grand-bruxelles-city-open-data-snapshot-shard-v1",
        "source": "City of Brussels Open Data",
        "api_base": API_BASE,
        "catalog_sha256": sha256_file(catalog_path),
        "catalog_dataset_count": len(rows),
        "shard_index": args.shard_index,
        "shard_count": args.shard_count,
        "selected_dataset_count": len(selected),
        "entries": entries,
        "failures": failures,
        "source_only": True,
        "runtime_authorized": False,
        "collision_authorized": False,
        "safe_spawn_authorized": False,
        "jouable_promotion_authorized": False,
    }
    write_json(root / "manifest.json", manifest)
    print(f"CITY_OPEN_DATA_SHARD_DONE shard={args.shard_index} selected={len(selected)} failures={len(failures)}")
    return 0 if not failures else 2


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    catalog = sub.add_parser("catalog")
    catalog.add_argument("--output", required=True)
    catalog.add_argument("--retries", type=int, default=7)
    catalog.set_defaults(func=command_catalog)
    shard = sub.add_parser("download-shard")
    shard.add_argument("--catalog", required=True)
    shard.add_argument("--output", required=True)
    shard.add_argument("--shard-index", type=int, required=True)
    shard.add_argument("--shard-count", type=int, required=True)
    shard.add_argument("--retries", type=int, default=7)
    shard.add_argument("--delay", type=float, default=0.15)
    shard.set_defaults(func=command_shard)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
