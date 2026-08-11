#!/usr/bin/env python3
"""Discover official Paradigm raster layers that may encode surface/DSM height."""

from __future__ import annotations

import json
import re
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path

CAPABILITIES_URL = "https://geoservices-grid.irisnet.be/geoserver/urbisgrid/ows?Service=WMS&Version=1.3.0&Request=GetCapabilities&Language=eng"
OUTPUT = Path("data/sources/laeken_jette/urbis_dsm_layer_discovery.json")
KEYWORDS = ("dsm", "digital surface", "surface model", "mns", "surface height", "height model", "elevation")
USER_AGENT = "Grand-Bruxelles-Game/1.0 (official DSM layer discovery)"


def child_text(node: ET.Element, suffix: str) -> str:
    for child in list(node):
        if child.tag.endswith(suffix):
            return (child.text or "").strip()
    return ""


def main() -> int:
    req = urllib.request.Request(CAPABILITIES_URL, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=60) as response:
        raw = response.read()
    root = ET.fromstring(raw)

    all_layers = []
    candidates = []
    for layer in root.iter():
        if not layer.tag.endswith("Layer"):
            continue
        name = child_text(layer, "Name")
        title = child_text(layer, "Title")
        abstract = child_text(layer, "Abstract")
        if not name:
            continue
        crs = [
            (child.text or "").strip()
            for child in list(layer)
            if child.tag.endswith("CRS") and (child.text or "").strip()
        ]
        record = {"name": name, "title": title, "abstract": abstract, "crs": crs}
        all_layers.append(record)
        haystack = f"{name} {title} {abstract}".lower()
        if any(keyword in haystack for keyword in KEYWORDS):
            candidates.append(record)

    output = {
        "schema": 1,
        "source": "Paradigm / Brussels-Capital Region official raster WMS",
        "capabilities_url": CAPABILITIES_URL,
        "fetched_at_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "layer_count": len(all_layers),
        "candidate_layers": candidates,
        "all_layers": all_layers,
        "policy": "This file only discovers authoritative raster layer names. No building height is inferred until a surface raster is proven to represent DSM/MNS metric elevation in EPSG:31370.",
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(output, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("LAEKEN_DSM_LAYER_DISCOVERY_OK", {"layers": len(all_layers), "candidates": len(candidates)})
    for candidate in candidates:
        print("DSM_CANDIDATE", candidate["name"], candidate["title"], candidate["crs"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
