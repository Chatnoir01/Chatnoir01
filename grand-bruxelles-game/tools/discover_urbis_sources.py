#!/usr/bin/env python3
"""Discover concrete UrbIS download distributions from official Atom feeds.

This tool intentionally records metadata first instead of downloading large datasets.
It extracts Atom entries and links (including enclosure links when provided) so the
project can decide which tiled/dated files intersect Brussels-Midi.
"""

from __future__ import annotations

import argparse
import json
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any

USER_AGENT = "GrandBruxellesGame/0.7 source-discovery (+github.com/Chatnoir01/Chatnoir01)"

DEFAULT_FEEDS = {
    "urbis_landscape": "https://urbisdownload.datastore.brussels/atomfeed/713171e6-65e3-11ef-b378-010101010000-en.xml",
    "urbis_dsm": "https://urbisdownload.datastore.brussels/atomfeed/8c2d921e-6a53-11ed-bfb5-010101010000-en.xml",
    "urbis_transport": "https://urbisdownload.datastore.brussels/atomfeed/af847c40-848b-11ee-9a1f-00090ffe0001-en.xml",
    "urbis_parcels_buildings": "https://urbisdownload.datastore.brussels/atomfeed/2cf42541-1813-11ef-8a81-00090ffe0001-en.xml",
}


def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def node_text(node: ET.Element | None) -> str | None:
    if node is None or node.text is None:
        return None
    value = node.text.strip()
    return value or None


def child_text(node: ET.Element, name: str) -> str | None:
    for child in node:
        if local_name(child.tag) == name:
            return node_text(child)
    return None


def extract_links(node: ET.Element) -> list[dict[str, str]]:
    links: list[dict[str, str]] = []
    for element in node.iter():
        if local_name(element.tag) != "link":
            continue
        href = element.attrib.get("href")
        if not href:
            continue
        item = {"href": href}
        for key in ("rel", "type", "title", "hreflang", "length"):
            if key in element.attrib:
                item[key] = element.attrib[key]
        links.append(item)
    return links


def fetch_xml(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()


def parse_feed(source_id: str, url: str) -> dict[str, Any]:
    raw = fetch_xml(url)
    root = ET.fromstring(raw)
    entries: list[dict[str, Any]] = []

    for element in root.iter():
        if local_name(element.tag) != "entry":
            continue
        entries.append(
            {
                "id": child_text(element, "id"),
                "title": child_text(element, "title"),
                "updated": child_text(element, "updated"),
                "published": child_text(element, "published"),
                "summary": child_text(element, "summary"),
                "links": extract_links(element),
            }
        )

    all_links = extract_links(root)
    concrete_files = []
    seen: set[str] = set()
    for link in all_links:
        href = link["href"]
        lower = href.lower().split("?", 1)[0]
        if not lower.endswith((".zip", ".gpkg", ".shp", ".gml", ".json", ".tif", ".tiff", ".xml")):
            continue
        if href in seen:
            continue
        seen.add(href)
        concrete_files.append(link)

    return {
        "source_id": source_id,
        "feed_url": url,
        "feed_title": child_text(root, "title"),
        "feed_updated": child_text(root, "updated"),
        "entry_count": len(entries),
        "entries": entries,
        "concrete_files": concrete_files,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    result = {
        "schema": 1,
        "purpose": "Official UrbIS distribution discovery for Grand Bruxelles Game",
        "feeds": [],
    }
    for source_id, url in DEFAULT_FEEDS.items():
        print(f"Discovering {source_id}: {url}")
        result["feeds"].append(parse_feed(source_id, url))

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8") as handle:
        json.dump(result, handle, ensure_ascii=False, indent=2)
        handle.write("\n")

    for feed in result["feeds"]:
        print(
            feed["source_id"],
            "entries=", feed["entry_count"],
            "files=", len(feed["concrete_files"]),
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
