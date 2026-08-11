#!/usr/bin/env python3
"""Discover administrative/submunicipal boundary layers in official UrbIS WFS.

The result is intentionally only a discovery manifest. No layer is promoted to
production solely because its name contains words such as district or quarter;
a follow-up inspection must prove the geometry and attributes identify the
required Brussels City subzones.
"""

from __future__ import annotations

import argparse
import json
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any

WFS_CAPABILITIES_URL = (
    "https://geoservices-urbis.irisnet.be/geoserver/urbisvector/wfs"
    "?service=WFS&request=GetCapabilities&version=2.0.0"
)
KEYWORDS = (
    "admin",
    "municip",
    "commune",
    "district",
    "quarter",
    "quartier",
    "wijk",
    "neigh",
    "sector",
    "secteur",
    "stat",
    "local",
    "town",
    "city",
)


def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def child_text(node: ET.Element, name: str) -> str:
    for child in node:
        if local_name(child.tag) == name:
            return (child.text or "").strip()
    return ""


def parse_feature_types(xml_bytes: bytes) -> list[dict[str, Any]]:
    root = ET.fromstring(xml_bytes)
    results: list[dict[str, Any]] = []
    for element in root.iter():
        if local_name(element.tag) != "FeatureType":
            continue
        name = child_text(element, "Name")
        title = child_text(element, "Title")
        abstract = child_text(element, "Abstract")
        default_crs = child_text(element, "DefaultCRS") or child_text(element, "DefaultSRS")
        haystack = " ".join((name, title, abstract)).lower()
        matched = sorted({keyword for keyword in KEYWORDS if keyword in haystack})
        if not matched:
            continue
        results.append(
            {
                "name": name,
                "title": title,
                "abstract": abstract,
                "default_crs": default_crs,
                "matched_keywords": matched,
            }
        )
    results.sort(key=lambda item: (item["name"], item["title"]))
    return results


def fetch_capabilities(url: str, timeout: int = 60) -> bytes:
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": "Grand-Bruxelles-Game/1.0 (+https://github.com/Chatnoir01/Chatnoir01)",
            "Accept": "application/xml,text/xml;q=0.9,*/*;q=0.1",
        },
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read()


def build_manifest(xml_bytes: bytes, source_url: str) -> dict[str, Any]:
    candidates = parse_feature_types(xml_bytes)
    return {
        "format": "grand-bruxelles-urbis-admin-layer-discovery-v1",
        "source": source_url,
        "purpose": "discover official submunicipal/administrative geometry candidates; candidates are not production-approved yet",
        "keyword_policy": list(KEYWORDS),
        "candidate_count": len(candidates),
        "candidates": candidates,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Discover administrative boundary candidates in UrbIS WFS")
    parser.add_argument("--url", default=WFS_CAPABILITIES_URL)
    parser.add_argument("--input", type=Path, help="optional local capabilities XML for offline/reproducible testing")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    xml_bytes = args.input.read_bytes() if args.input else fetch_capabilities(args.url)
    manifest = build_manifest(xml_bytes, args.url)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"UrbIS administrative discovery: {manifest['candidate_count']} candidates -> {args.output}")
    for candidate in manifest["candidates"]:
        print(f"  {candidate['name']} | {candidate['title']} | {candidate['matched_keywords']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
