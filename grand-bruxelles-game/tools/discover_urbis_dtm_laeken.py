#!/usr/bin/env python3
"""Discover official Paradigm UrbIS 2021 DTM distributions for Laeken."""

from __future__ import annotations

import json
import re
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path

FEED_URL = "https://urbisdownload.datastore.brussels/atomfeed/1d7bd49d-fe83-4388-af85-6f5dc8ec7909-en.xml"
DATASET_ID = "1d7bd49d-fe83-4388-af85-6f5dc8ec7909"
BBOX = (147300.0, 173650.0, 149100.0, 176750.0)
OUTPUT = Path("data/sources/laeken_jette/urbis_dtm_discovery.json")
USER_AGENT = "Grand-Bruxelles-Game/1.0 (UrbIS DTM source inventory)"


def fetch(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=45) as response:
        return response.read()


def expected_tiles() -> list[str]:
    min_e, min_n, max_e, max_n = BBOX
    return [
        f"{e:03d}{n:03d}"
        for e in range(int(min_e // 1000), int(max_e // 1000) + 1)
        for n in range(int(min_n // 1000), int(max_n // 1000) + 1)
    ]


def extract_urls(raw: bytes, base: str) -> set[str]:
    result: set[str] = set()
    try:
        root = ET.fromstring(raw)
    except ET.ParseError:
        text = raw.decode("utf-8", errors="ignore")
        return set(re.findall(r"https?://[^\s\"'<>]+", text))
    for element in root.iter():
        for key in ("href", "src"):
            value = element.attrib.get(key)
            if value:
                result.add(urllib.parse.urljoin(base, value))
        text = (element.text or "").strip()
        if text.startswith("https://") or text.startswith("http://"):
            result.add(text)
    return result


def main() -> int:
    raw = fetch(FEED_URL)
    links = extract_urls(raw, FEED_URL)
    tiles = expected_tiles()
    candidates = []
    for url in sorted(links):
        lower = url.lower()
        matching = [tile for tile in tiles if tile in url]
        if matching or any(ext in lower for ext in (".tif", ".tiff", ".zip", "dtm", "mnt", "terrain")):
            candidates.append({"url": url, "matching_tiles": matching})

    output = {
        "schema": 1,
        "source": "Paradigm UrbIS Digital Terrain Model 2021",
        "dataset_id": DATASET_ID,
        "dataset_atom_feed": FEED_URL,
        "bbox_epsg31370": list(BBOX),
        "expected_1km_tile_codes": tiles,
        "fetched_at_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "feed_bytes": len(raw),
        "discovered_link_count": len(links),
        "candidate_links": candidates,
        "policy": "Terrain will only be generated from an official DTM distribution discovered through this feed.",
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(output, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("LAEKEN_DTM_DISCOVERY_OK", {"links": len(links), "candidates": len(candidates)})
    for item in candidates:
        if item["matching_tiles"]:
            print("MATCH", item["matching_tiles"], item["url"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
