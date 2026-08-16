#!/usr/bin/env python3
"""Resolve exact official Paradigm DSM/DTM archives required by one CityGen cell.

This stage resolves URLs only. It never downloads archives, validates raster
content, or flips terrain/height maturity gates. Resolution is fail-closed: each
required 1 km tile must map to exactly one ZIP on the official datastore host.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any, Callable

FORMAT = "grand-bruxelles-cell-elevation-source-resolution-v1"
REQUIREMENTS_FORMAT = "grand-bruxelles-cell-elevation-requirements-v1"
OFFICIAL_HOST = "urbisdownload.datastore.brussels"
USER_AGENT = "Grand-Bruxelles-Game/1.0 (authoritative elevation source resolution)"


def _read(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def _digest(value: Any) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")).hexdigest()


def fetch(url: str) -> bytes:
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme != "https" or (parsed.hostname or "").lower() != OFFICIAL_HOST:
        raise ValueError(f"elevation feed must use official HTTPS host {OFFICIAL_HOST}: {url}")
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/atom+xml, application/xml, text/xml"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()


def extract_urls(raw: bytes, base_url: str) -> set[str]:
    try:
        root = ET.fromstring(raw)
    except ET.ParseError:
        text = raw.decode("utf-8", errors="ignore")
        candidates = re.findall(r"https?://[^\s\"'<>]+", text)
        return {urllib.parse.urljoin(base_url, value) for value in candidates}
    urls: set[str] = set()
    for element in root.iter():
        for key in ("href", "src"):
            value = element.attrib.get(key)
            if value:
                urls.add(urllib.parse.urljoin(base_url, value))
        text = (element.text or "").strip()
        if text.startswith(("https://", "http://")):
            urls.add(urllib.parse.urljoin(base_url, text))
    return urls


def _is_crawlable(url: str) -> bool:
    parsed = urllib.parse.urlparse(url)
    if (parsed.hostname or "").lower() != OFFICIAL_HOST:
        return False
    low = parsed.path.lower()
    return low.endswith(".xml") or "atomfeed" in low or "feed" in low


def crawl(start_url: str, fetcher: Callable[[str], bytes] = fetch, max_depth: int = 2) -> tuple[list[dict[str, Any]], set[str]]:
    queue = [(start_url, 0)]
    seen: set[str] = set()
    records: list[dict[str, Any]] = []
    links: set[str] = set()
    while queue:
        url, depth = queue.pop(0)
        if url in seen or depth > max_depth:
            continue
        parsed = urllib.parse.urlparse(url)
        if parsed.scheme != "https" or (parsed.hostname or "").lower() != OFFICIAL_HOST:
            raise ValueError(f"crawl escaped official elevation host: {url}")
        seen.add(url)
        raw = fetcher(url)
        found = extract_urls(raw, url)
        records.append({"url": url, "depth": depth, "bytes": len(raw), "links": len(found)})
        links.update(found)
        if depth < max_depth:
            for child in sorted(found):
                if child not in seen and _is_crawlable(child):
                    queue.append((child, depth + 1))
    return records, links


def _resolve_tiles(links: set[str], expected_tiles: list[str]) -> list[dict[str, str]]:
    resolved: list[dict[str, str]] = []
    for tile in expected_tiles:
        matches: list[str] = []
        for url in links:
            parsed = urllib.parse.urlparse(url)
            if parsed.scheme != "https" or (parsed.hostname or "").lower() != OFFICIAL_HOST:
                continue
            filename = Path(parsed.path).name
            if filename.lower().endswith(".zip") and tile in filename:
                matches.append(url)
        matches = sorted(set(matches))
        if len(matches) != 1:
            raise ValueError(f"expected exactly one official ZIP for tile {tile}, found {matches}")
        resolved.append({"tile": tile, "url": matches[0]})
    return resolved


def build(requirements_path: Path, kind: str, fetcher: Callable[[str], bytes] = fetch) -> dict[str, Any]:
    requirements = _read(requirements_path)
    if requirements.get("format") != REQUIREMENTS_FORMAT:
        raise ValueError("unsupported elevation requirements format")
    if requirements.get("crs") != "EPSG:31370":
        raise ValueError("elevation requirements CRS mismatch")
    if kind not in ("dsm", "dtm"):
        raise ValueError(f"unsupported elevation kind: {kind}")
    source = (requirements.get("official_sources") or {}).get(kind)
    if not isinstance(source, dict):
        raise ValueError(f"requirements missing official {kind} source")
    feed = source.get("atom_feed")
    if not isinstance(feed, str):
        raise ValueError(f"requirements missing {kind} Atom feed")
    expected = requirements.get("expected_1km_tile_codes")
    if not isinstance(expected, list) or not expected or not all(isinstance(v, str) and len(v) == 6 and v.isdigit() for v in expected):
        raise ValueError("invalid required elevation tile list")
    feeds, links = crawl(feed, fetcher)
    result = {
        "format": FORMAT,
        "cell_id": requirements.get("cell_id"),
        "kind": kind,
        "crs": "EPSG:31370",
        "bbox": requirements.get("bbox"),
        "dataset_id": source.get("dataset_id"),
        "dataset_atom_feed": feed,
        "expected_1km_tile_codes": expected,
        "feeds_crawled": feeds,
        "resolved_archives": _resolve_tiles(links, expected),
        "status": "official_archives_resolved_not_downloaded_or_validated",
        "maturity_effect": {
            "terrain_gate": False,
            "heights_gate": False,
            "reason": "urls_only_no_raster_validation",
        },
    }
    result["resolution_digest"] = _digest(result)
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--requirements", type=Path, required=True)
    parser.add_argument("--kind", choices=("dsm", "dtm"), required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = build(args.requirements, args.kind)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("CELL_ELEVATION_SOURCE_RESOLUTION_OK", result["cell_id"], result["kind"], len(result["resolved_archives"]), result["resolution_digest"])


if __name__ == "__main__":
    main()
