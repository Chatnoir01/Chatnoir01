#!/usr/bin/env python3
"""Discover official UrbIS Digital Surface Model distributions for Laeken."""

from __future__ import annotations

import json
import re
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path

FEED_URL = "https://urbisdownload.datastore.brussels/atomfeed/8c2d921e-6a53-11ed-bfb5-010101010000-en.xml"
DATASET_ID = "8c2d921e-6a53-11ed-bfb5-010101010000"
BBOX = (147300.0, 173650.0, 149100.0, 176750.0)
OUTPUT = Path("data/sources/laeken_jette/urbis_dsm_discovery.json")
USER_AGENT = "Grand-Bruxelles-Game/1.0 (UrbIS DSM source inventory)"


def fetch(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()


def expected_tiles() -> list[str]:
    min_e, min_n, max_e, max_n = BBOX
    return [
        f"{e:03d}{n:03d}"
        for e in range(int(min_e // 1000), int(max_e // 1000) + 1)
        for n in range(int(min_n // 1000), int(max_n // 1000) + 1)
    ]


def extract_urls(raw: bytes, base: str) -> set[str]:
    urls: set[str] = set()
    try:
        root = ET.fromstring(raw)
    except ET.ParseError:
        text = raw.decode("utf-8", errors="ignore")
        return set(re.findall(r"https?://[^\s\"'<>]+", text))
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


def crawl(start: str, depth: int = 2) -> tuple[list[dict], set[str]]:
    queue = [(start, 0)]
    seen: set[str] = set()
    records = []
    links: set[str] = set()
    while queue:
        url, level = queue.pop(0)
        if url in seen or level > depth:
            continue
        seen.add(url)
        try:
            raw = fetch(url)
            found = extract_urls(raw, url)
            records.append({"url": url, "depth": level, "bytes": len(raw), "links": len(found)})
            links.update(found)
            if level < depth:
                for child in sorted(found):
                    host = urllib.parse.urlparse(child).hostname or ""
                    if host.endswith("datastore.brussels") and looks_like_feed(child):
                        queue.append((child, level + 1))
        except Exception as exc:
            records.append({"url": url, "depth": level, "error": repr(exc)})
    return records, links


def main() -> int:
    tiles = expected_tiles()
    feeds, links = crawl(FEED_URL)
    candidates = []
    for url in sorted(links):
        matching = [tile for tile in tiles if tile in url]
        low = url.lower()
        if matching or any(token in low for token in ("dsm", "surface", ".tif", ".tiff", ".zip")):
            candidates.append({"url": url, "matching_tiles": matching})

    output = {
        "schema": 1,
        "source": "Paradigm UrbIS Digital Surface Model",
        "dataset_id": DATASET_ID,
        "dataset_atom_feed": FEED_URL,
        "source_license": "CC0 per official Geobru ISO metadata",
        "source_crs_target": "EPSG:31370",
        "bbox_epsg31370": list(BBOX),
        "expected_1km_tile_codes": tiles,
        "fetched_at_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "feeds_crawled": feeds,
        "all_discovered_link_count": len(links),
        "candidate_links": candidates,
        "policy": "DSM is used only as metric surface elevation. Building heights are derived as robust DSM minus DTM statistics inside official UrbIS building footprints.",
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(output, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("LAEKEN_DSM_DISCOVERY_OK", {"feeds": len(feeds), "links": len(links), "candidates": len(candidates)})
    for candidate in candidates:
        if candidate["matching_tiles"]:
            print("DSM_MATCH", candidate["matching_tiles"], candidate["url"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
