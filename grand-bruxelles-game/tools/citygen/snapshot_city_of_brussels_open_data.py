#!/usr/bin/env python3
"""Snapshot every public City of Brussels Open Data dataset as source-only evidence.

The tool discovers the catalogue once through Explore API v2.1, then downloads the
complete JSON export for every dataset with records. It supports deterministic
sharding for GitHub Actions. Federated catalogue entries whose municipal export is
unavailable may be recovered from the public Opendatasoft Data Hub using the City
of Brussels domain identity. A specifically proven retired federated export is
accounted as metadata-only rather than substituted with an unproven mirror.
Nothing produced here authorizes runtime/game use.
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
DATA_HUB_API_BASE = "https://data.opendatasoft.com/api/explore/v2.1"
DATA_HUB_DOMAIN_ID = "bruxellesdata"
USER_AGENT = "Grand-Bruxelles-Game-OpenData-Snapshot/1.0"

# RED-first run 32879741993 proved the City complete-export endpoint returns 404.
# Exact-head run 32880206920 then proved the same City-domain Data Hub identity
# also returns 404, while the catalogue entry remains present, federated=true,
# has_records=true. The portal table itself currently reports Resource not found.
# Do not silently replace this with a similarly named public mirror: preserve the
# catalogue metadata and fail closed on the unavailable source bytes.
KNOWN_RETIRED_FEDERATED_EXPORTS = {
    "pandemie-covid-19-nombre-de-cas-confirmes-par-date-age-et-genre-belgique"
}


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


def _default_meta(row: dict[str, Any]) -> dict[str, Any]:
    metas = row.get("metas") if isinstance(row.get("metas"), dict) else {}
    default = metas.get("default") if isinstance(metas.get("default"), dict) else {}
    return default


def _dataset_meta(row: dict[str, Any]) -> dict[str, Any]:
    default = _default_meta(row)
    return {
        "dataset_id": row["dataset_id"],
        "title": default.get("title"),
        "license": default.get("license"),
        "records_count_catalog": default.get("records_count"),
        "has_records": bool(row.get("has_records")),
        "federated": bool(default.get("federated")),
    }


def export_candidates(row: dict[str, Any]) -> list[dict[str, Any]]:
    """Return fail-closed complete-export candidates in authority order.

    The City portal is always authoritative first. If the catalogue explicitly
    marks the dataset as federated, Opendatasoft's public Data Hub can expose the
    same City dataset under `<dataset_id>@bruxellesdata`. This is a recovery path
    for a municipal export endpoint that returns 404; it is never used for a
    non-federated entry and never falls back to partial /records pagination.
    """
    dataset_id = str(row["dataset_id"])
    candidates = [
        {
            "api_base": API_BASE,
            "dataset_id": dataset_id,
            "federated_fallback": False,
        }
    ]
    if bool(_default_meta(row).get("federated")):
        candidates.append(
            {
                "api_base": DATA_HUB_API_BASE,
                "dataset_id": f"{dataset_id}@{DATA_HUB_DOMAIN_ID}",
                "federated_fallback": True,
            }
        )
    return candidates


def _export_url(api_base: str, dataset_id: str) -> str:
    quoted = urllib.parse.quote(dataset_id, safe="")
    return f"{api_base}/catalog/datasets/{quoted}/exports/json?timezone=UTC&use_labels=false"


def _stream_export(url: str, output: Path, retries: int) -> tuple[str, int]:
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
            raise RuntimeError(f"empty export: {url}")
        os.replace(partial, output)
        return digest.hexdigest(), size
    finally:
        partial.unlink(missing_ok=True)


def download_export(row: dict[str, Any], output: Path, retries: int = 7) -> tuple[str, int, dict[str, Any]]:
    output.parent.mkdir(parents=True, exist_ok=True)
    candidates = export_candidates(row)
    primary_404: urllib.error.HTTPError | None = None
    for index, candidate in enumerate(candidates):
        url = _export_url(str(candidate["api_base"]), str(candidate["dataset_id"]))
        try:
            digest, size = _stream_export(url, output, retries)
            evidence = dict(candidate)
            evidence["url"] = url
            if candidate["federated_fallback"]:
                print(
                    f"FEDERATED_EXPORT_RECOVERED city_dataset={row['dataset_id']} "
                    f"hub_dataset={candidate['dataset_id']} bytes={size} sha256={digest}"
                )
            return digest, size, evidence
        except urllib.error.HTTPError as exc:
            if index == 0 and exc.code == 404 and len(candidates) > 1:
                primary_404 = exc
                print(
                    f"FEDERATED_EXPORT_PRIMARY_404 dataset={row['dataset_id']} "
                    f"fallback={candidates[1]['dataset_id']}",
                    file=sys.stderr,
                )
                continue
            raise
    if primary_404 is not None:
        raise primary_404
    raise RuntimeError(f"no complete export candidate for {row['dataset_id']}")


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
    unavailable_complete_exports: list[dict[str, Any]] = []
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
            digest, size, retrieval = download_export(row, path, retries=args.retries)
            Path(str(path) + ".sha256").write_text(f"{digest}  {path.name}\n", encoding="utf-8")
            entry.update(
                {
                    "status": "downloaded",
                    "file": f"datasets/{token}.json",
                    "sha256": digest,
                    "bytes": size,
                    "retrieval": retrieval,
                }
            )
        except urllib.error.HTTPError as exc:
            if (
                exc.code == 404
                and entry["federated"] is True
                and dataset_id in KNOWN_RETIRED_FEDERATED_EXPORTS
            ):
                attempted = []
                for candidate in export_candidates(row):
                    item = dict(candidate)
                    item["url"] = _export_url(str(candidate["api_base"]), str(candidate["dataset_id"]))
                    item["observed_http_status"] = 404
                    attempted.append(item)
                unavailable = {
                    "dataset_id": dataset_id,
                    "catalog_has_records": True,
                    "catalog_federated": True,
                    "records_count_catalog": entry["records_count_catalog"],
                    "attempted_complete_exports": attempted,
                    "status": "KNOWN_RETIRED_FEDERATED_COMPLETE_EXPORT_UNAVAILABLE",
                    "substitute_used": False,
                }
                entry.update(
                    {
                        "status": "metadata_only_federated_complete_export_unavailable",
                        "complete_export_unavailable": True,
                        "attempted_complete_exports": attempted,
                        "substitute_used": False,
                    }
                )
                unavailable_complete_exports.append(unavailable)
                print(
                    f"FEDERATED_EXPORT_RETIRED_ACCOUNTED id={dataset_id} "
                    f"records_catalog={entry['records_count_catalog']} substitute=false"
                )
            else:
                entry.update({"status": "failed", "error": str(exc)})
                failures.append({"dataset_id": dataset_id, "error": str(exc)})
                print(f"SHARD_FAILURE id={dataset_id} error={exc!r}", file=sys.stderr)
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
        "federated_fallback_api_base": DATA_HUB_API_BASE,
        "federated_domain_id": DATA_HUB_DOMAIN_ID,
        "catalog_sha256": sha256_file(catalog_path),
        "catalog_dataset_count": len(rows),
        "shard_index": args.shard_index,
        "shard_count": args.shard_count,
        "selected_dataset_count": len(selected),
        "entries": entries,
        "failures": failures,
        "unavailable_complete_exports": unavailable_complete_exports,
        "source_only": True,
        "runtime_authorized": False,
        "collision_authorized": False,
        "safe_spawn_authorized": False,
        "jouable_promotion_authorized": False,
    }
    write_json(root / "manifest.json", manifest)
    print(
        f"CITY_OPEN_DATA_SHARD_DONE shard={args.shard_index} selected={len(selected)} "
        f"unavailable={len(unavailable_complete_exports)} failures={len(failures)}"
    )
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
