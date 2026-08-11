#!/usr/bin/env python3
"""Discover official UrbIS WFS layers useful for Laeken environmental realism."""

from __future__ import annotations

import json
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path

WFS = "https://geoservices-urbis.irisnet.be/geoserver/urbisvector/wfs"
OUTPUT = Path("data/sources/laeken_jette/urbis_environment_layer_discovery.json")
KEYWORDS = (
    "tree", "veget", "green", "park", "garden", "wood", "forest",
    "water", "pond", "lake", "river", "canal", "hydro", "landscape",
    "streetfurniture", "furniture", "light", "lamp",
)
USER_AGENT = "Grand-Bruxelles-Game/1.0 (UrbIS environmental layer discovery)"


def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def child_text(node: ET.Element, name: str) -> str:
    for child in list(node):
        if local_name(child.tag) == name:
            return (child.text or "").strip()
    return ""


def main() -> int:
    url = WFS + "?service=WFS&version=2.0.0&request=GetCapabilities"
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=60) as response:
        raw = response.read()
    root = ET.fromstring(raw)

    all_types = []
    candidates = []
    for node in root.iter():
        if local_name(node.tag) != "FeatureType":
            continue
        name = child_text(node, "Name")
        title = child_text(node, "Title")
        abstract = child_text(node, "Abstract")
        default_crs = child_text(node, "DefaultCRS")
        if not name:
            continue
        record = {
            "name": name,
            "title": title,
            "abstract": abstract,
            "default_crs": default_crs,
        }
        all_types.append(record)
        haystack = f"{name} {title} {abstract}".lower()
        matched = [keyword for keyword in KEYWORDS if keyword in haystack]
        if matched:
            candidates.append(record | {"matched_keywords": matched})

    output = {
        "schema": 1,
        "source": "Paradigm UrbIS vector WFS GetCapabilities",
        "wfs": WFS,
        "fetched_at_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "feature_type_count": len(all_types),
        "candidate_count": len(candidates),
        "candidates": candidates,
        "all_feature_types": all_types,
        "policy": "Only authoritative feature types discovered here are eligible for the next Laeken environment import. OSM is used only when UrbIS has no equivalent layer.",
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(output, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("URBIS_ENVIRONMENT_DISCOVERY_OK", len(all_types), len(candidates))
    for item in candidates:
        print("ENV_CANDIDATE", item["name"], item["title"], item["matched_keywords"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
