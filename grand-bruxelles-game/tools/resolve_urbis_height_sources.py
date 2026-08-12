#!/usr/bin/env python3
"""Resolve exact official UrbIS DSM/DTM archives for a height tile plan."""

from __future__ import annotations

import argparse
import json
import re
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

USER_AGENT = "Grand-Bruxelles-Game/1.0 (authoritative height source resolution)"


def fetch(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=60) as response:
        return response.read()


def extract_urls(raw: bytes, base: str) -> set[str]:
    try:
        root = ET.fromstring(raw)
    except ET.ParseError:
        text = raw.decode("utf-8", errors="ignore")
        return set(re.findall(r"https?://[^\s\"'<>]+", text))
    urls: set[str] = set()
    for element in root.iter():
        for key in ("href", "src"):
            value = element.attrib.get(key)
            if value:
                urls.add(urllib.parse.urljoin(base, value))
        text = (element.text or "").strip()
        if text.startswith(("http://", "https://")):
            urls.add(text)
    return urls


def looks_like_feed(url: str) -> bool:
    low = url.lower()
    return low.endswith(".xml") or "atomfeed" in low or "feed" in low


def crawl(start: str, max_depth: int = 2) -> tuple[list[dict], set[str]]:
    queue = [(start, 0)]
    seen: set[str] = set()
    records: list[dict] = []
    links: set[str] = set()
    while queue:
        url, depth = queue.pop(0)
        if url in seen or depth > max_depth:
            continue
        seen.add(url)
        raw = fetch(url)
        found = extract_urls(raw, url)
        records.append({"url": url, "depth": depth, "bytes": len(raw), "links": len(found)})
        links.update(found)
        if depth < max_depth:
            for child in sorted(found):
                host = urllib.parse.urlparse(child).hostname or ""
                if host.endswith("datastore.brussels") and looks_like_feed(child):
                    queue.append((child, depth + 1))
    return records, links


def resolve_links(links: set[str], expected_tiles: list[str]) -> dict[str, str]:
    resolved: dict[str, str] = {}
    for tile in expected_tiles:
        matches = sorted({url for url in links if url.lower().endswith(".zip") and tile in Path(urllib.parse.urlparse(url).path).name})
        if len(matches) != 1:
            raise ValueError(f"Expected exactly one official archive for tile {tile}, found {matches}")
        resolved[tile] = matches[0]
    return resolved


def build_resolution(plan: dict, kind: str, feeds: list[dict], links: set[str]) -> dict:
    if kind not in ("dsm", "dtm"):
        raise ValueError(f"Unsupported height source kind: {kind}")
    source = plan["official_sources"][kind]
    expected = list(plan["expected_1km_tile_codes"])
    resolved = resolve_links(links, expected)
    return {
        "schema": 1,
        "format": "grand-bruxelles-height-source-resolution-v1",
        "kind": kind,
        "source": source["name"],
        "dataset_id": source["dataset_id"],
        "dataset_atom_feed": source["atom_feed"],
        "source_crs": plan["source_crs"],
        "bbox_epsg31370": plan["bbox_epsg31370"],
        "expected_1km_tile_codes": expected,
        "feeds_crawled": feeds,
        "resolved_archives": [{"tile": tile, "url": resolved[tile]} for tile in expected],
        "license": "CC0 per official Paradigm/Geobru metadata recorded by the project",
        "status": "official_archives_resolved_not_yet_downloaded_or_hashed",
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--kind", choices=("dsm", "dtm"), required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    plan = json.loads(args.plan.read_text(encoding="utf-8"))
    source = plan["official_sources"][args.kind]
    feeds, links = crawl(source["atom_feed"])
    resolution = build_resolution(plan, args.kind, feeds, links)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(resolution, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("URBIS_HEIGHT_SOURCE_RESOLUTION_OK", args.kind, resolution["expected_1km_tile_codes"])
    for item in resolution["resolved_archives"]:
        print("HEIGHT_SOURCE", args.kind, item["tile"], item["url"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
