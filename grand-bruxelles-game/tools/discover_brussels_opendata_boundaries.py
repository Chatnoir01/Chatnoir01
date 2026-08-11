#!/usr/bin/env python3
"""Discover official Brussels open-data datasets likely to contain area boundaries.

Uses the public Opendatasoft Explore v2.1 catalog API on opendata.brussels.be.
Discovery is deliberately broad and evidence-only; a dataset must later prove
that target place names are carried by Polygon/MultiPolygon records before it is
used for game geometry.
"""

from __future__ import annotations

import argparse
import json
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

API = "https://opendata.brussels.be/api/explore/v2.1/catalog/datasets"
DEFAULT_TERMS = (
    "quartier",
    "quartiers",
    "wijk",
    "district",
    "secteur",
    "sector",
    "monitoring",
    "statistique",
    "statistical",
    "neighborhood",
    "boundary",
    "limite",
)


def request_json(url: str, timeout: int = 60) -> dict[str, Any]:
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": "Grand-Bruxelles-Game/1.0 (+https://github.com/Chatnoir01/Chatnoir01)",
            "Accept": "application/json",
        },
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8"))


def search_url(term: str, limit: int = 50) -> str:
    params = {"limit": str(limit), "where": f'search("{term}")'}
    return API + "?" + urllib.parse.urlencode(params)


def meta_text(record: dict[str, Any], key: str) -> str:
    metas = record.get("metas") or {}
    default = metas.get("default") or {}
    value = default.get(key)
    return str(value or "").strip()


def normalize_record(record: dict[str, Any], matched_terms: set[str]) -> dict[str, Any]:
    return {
        "dataset_id": str(record.get("dataset_id") or ""),
        "title": meta_text(record, "title"),
        "description": meta_text(record, "description"),
        "publisher": meta_text(record, "publisher"),
        "license": meta_text(record, "license"),
        "records_count": record.get("records_count") or (record.get("metas") or {}).get("default", {}).get("records_count"),
        "has_records": bool(record.get("has_records", False)),
        "visibility": str(record.get("visibility") or ""),
        "matched_terms": sorted(matched_terms),
    }


def discover(terms: list[str], limit: int = 50) -> dict[str, Any]:
    by_id: dict[str, tuple[dict[str, Any], set[str]]] = {}
    searches: list[dict[str, Any]] = []
    for term in terms:
        payload = request_json(search_url(term, limit))
        results = payload.get("results") or []
        searches.append({"term": term, "total_count": int(payload.get("total_count", len(results))), "returned": len(results)})
        for record in results:
            if not isinstance(record, dict):
                continue
            dataset_id = str(record.get("dataset_id") or "").strip()
            if not dataset_id:
                continue
            if dataset_id not in by_id:
                by_id[dataset_id] = (record, set())
            by_id[dataset_id][1].add(term)
    datasets = [normalize_record(record, matched) for record, matched in by_id.values()]
    datasets.sort(key=lambda item: (-len(item["matched_terms"]), item["title"].casefold(), item["dataset_id"]))
    return {
        "format": "grand-bruxelles-opendata-boundary-discovery-v1",
        "source": API,
        "purpose": "discover official boundary dataset candidates; no candidate is production-approved by discovery alone",
        "search_terms": terms,
        "searches": searches,
        "candidate_count": len(datasets),
        "candidates": datasets,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Discover official Brussels open-data boundary datasets")
    parser.add_argument("--term", action="append", default=[])
    parser.add_argument("--limit", type=int, default=50)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    terms = args.term or list(DEFAULT_TERMS)
    result = discover(terms, max(1, min(args.limit, 100)))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"official Brussels open-data discovery: {result['candidate_count']} unique datasets")
    for item in result["candidates"][:30]:
        print(f"  {item['dataset_id']} | {item['title']} | terms={item['matched_terms']} | records={item['records_count']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
