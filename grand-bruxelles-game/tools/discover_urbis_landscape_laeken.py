#!/usr/bin/env python3
"""Discover official UrbIS Landscape distributions relevant to Laeken phase 1.

This tool intentionally does not guess terrain. It reads the Paradigm Atom feed
for UrbIS Landscape and inventories links/distributions that can cover the
Bockstael-Heysel-Atomium bbox. The output is committed as source provenance and
used by the next terrain/3D import step.
"""

from __future__ import annotations

import json
import re
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

FEED_URL = "https://urbisdownload.datastore.brussels/atomfeed/713171e6-65e3-11ef-b378-010101010000-en.xml"
BBOX = (147300.0, 173650.0, 149100.0, 176750.0)
OUTPUT = Path("data/sources/laeken_jette/urbis_landscape_discovery.json")
USER_AGENT = "Grand-Bruxelles-Game/1.0 (UrbIS Landscape source inventory)"


def fetch(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=45) as response:
        return response.read()


def expected_tile_codes() -> list[str]:
    min_e, min_n, max_e, max_n = BBOX
    e_values = range(int(min_e // 1000), int(max_e // 1000) + 1)
    n_values = range(int(min_n // 1000), int(max_n // 1000) + 1)
    return [f"{e:03d}{n:03d}" for e in e_values for n in n_values]


def extract_urls(xml_bytes: bytes, base_url: str) -> set[str]:
    urls: set[str] = set()
    try:
        root = ET.fromstring(xml_bytes)
    except ET.ParseError:
        text = xml_bytes.decode("utf-8", errors="ignore")
        for match in re.findall(r"https?://[^\s\"'<>]+", text):
            urls.add(match.replace("&amp;", "&"))
        return urls

    for element in root.iter():
        for key in ("href", "src"):
            value = element.attrib.get(key)
            if value:
                urls.add(urllib.parse.urljoin(base_url, value))
        text = (element.text or "").strip()
        if text.startswith("http://") or text.startswith("https://"):
            urls.add(text)
    return urls


def looks_like_feed(url: str) -> bool:
    lowered = url.lower()
    return lowered.endswith(".xml") or "atomfeed" in lowered or "feed" in lowered


def crawl_feed(start_url: str, depth: int = 2) -> tuple[list[dict], set[str]]:
    queue: list[tuple[str, int]] = [(start_url, 0)]
    seen: set[str] = set()
    feed_records: list[dict] = []
    links: set[str] = set()

    while queue:
        url, level = queue.pop(0)
        if url in seen or level > depth:
            continue
        seen.add(url)
        try:
            raw = fetch(url)
        except Exception as exc:  # network/service detail belongs in inventory
            feed_records.append({"url": url, "depth": level, "error": repr(exc)})
            continue
        found = extract_urls(raw, url)
        feed_records.append({"url": url, "depth": level, "bytes": len(raw), "links": len(found)})
        links.update(found)
        if level < depth:
            for child in sorted(found):
                host = urllib.parse.urlparse(child).hostname or ""
                if host.endswith("datastore.brussels") and looks_like_feed(child):
                    queue.append((child, level + 1))
    return feed_records, links


def relevant_links(links: Iterable[str], tile_codes: list[str]) -> list[dict]:
    result: list[dict] = []
    for url in sorted(set(links)):
        lower = url.lower()
        matching_tiles = [tile for tile in tile_codes if tile in url]
        landscape_hint = any(token in lower for token in ("landscape", "urbislandscape", "3d", "dtm", "terrain", "skp"))
        file_hint = any(lower.endswith(ext) for ext in (".zip", ".skp", ".gml", ".xml", ".json", ".tif", ".tiff"))
        if matching_tiles or (landscape_hint and file_hint):
            result.append({
                "url": url,
                "matching_tiles": matching_tiles,
                "landscape_hint": landscape_hint,
            })
    return result


def main() -> int:
    tile_codes = expected_tile_codes()
    feeds, links = crawl_feed(FEED_URL)
    candidates = relevant_links(links, tile_codes)

    output = {
        "schema": 1,
        "source": "Paradigm UrbIS Landscape",
        "dataset_id": "713171e6-65e3-11ef-b378-010101010000",
        "dataset_atom_feed": FEED_URL,
        "purpose": "Laeken Bockstael-Heysel-Atomium terrain and 3D source discovery",
        "source_crs_target": "EPSG:31370",
        "bbox_epsg31370": list(BBOX),
        "expected_1km_tile_codes": tile_codes,
        "fetched_at_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "feeds_crawled": feeds,
        "candidate_links": candidates,
        "all_discovered_link_count": len(links),
        "policy": "No terrain or building height is inferred from this inventory; only discovered official distributions may feed the next import stage.",
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(output, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    print("Expected tile codes:", ", ".join(tile_codes))
    print("Feeds crawled:", len(feeds))
    print("Links discovered:", len(links))
    print("Relevant candidates:", len(candidates))
    for candidate in candidates[:100]:
        print("CANDIDATE", candidate["matching_tiles"], candidate["url"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
