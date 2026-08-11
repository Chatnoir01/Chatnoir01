#!/usr/bin/env python3
"""Inventory official Paradigm raster WMS metadata for Laeken orthophoto use."""

from __future__ import annotations

import json
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path

CAPABILITIES_URL = "https://geoservices-grid.irisnet.be/geoserver/urbisgrid/ows?Service=WMS&Version=1.3.0&Request=GetCapabilities&Language=eng"
TARGET_LAYERS = {"Ortho2024Ns", "Ortho2024Eo", "Ortho"}
OUTPUT = Path("data/sources/laeken_jette/orthophoto_wms_inventory.json")
USER_AGENT = "Grand-Bruxelles-Game/1.0 (orthophoto provenance inventory)"


def text_of(parent: ET.Element | None, suffix: str) -> str | None:
    if parent is None:
        return None
    for child in list(parent):
        if child.tag.endswith(suffix):
            text = (child.text or "").strip()
            return text or None
    return None


def main() -> int:
    request = urllib.request.Request(CAPABILITIES_URL, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=60) as response:
        raw = response.read()
    root = ET.fromstring(raw)

    service = next((node for node in root.iter() if node.tag.endswith("Service")), None)
    service_meta = {
        "name": text_of(service, "Name"),
        "title": text_of(service, "Title"),
        "abstract": text_of(service, "Abstract"),
        "fees": text_of(service, "Fees"),
        "access_constraints": text_of(service, "AccessConstraints"),
    }

    layers = []
    for layer in root.iter():
        if not layer.tag.endswith("Layer"):
            continue
        name = text_of(layer, "Name")
        if name not in TARGET_LAYERS:
            continue
        crs = []
        bounding_boxes = []
        for child in list(layer):
            if child.tag.endswith("CRS"):
                value = (child.text or "").strip()
                if value:
                    crs.append(value)
            elif child.tag.endswith("BoundingBox"):
                bounding_boxes.append(dict(child.attrib))
        layers.append({
            "name": name,
            "title": text_of(layer, "Title"),
            "abstract": text_of(layer, "Abstract"),
            "crs": crs,
            "bounding_boxes": bounding_boxes,
        })

    output = {
        "schema": 1,
        "source": "Paradigm / Brussels-Capital Region official raster WMS",
        "capabilities_url": CAPABILITIES_URL,
        "fetched_at_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "capabilities_bytes": len(raw),
        "service": service_meta,
        "target_layers": layers,
        "phase1_bbox_epsg31370": [147300.0, 173650.0, 149100.0, 176750.0],
        "policy": "Orthophoto imagery is not redistributed until service/dataset access and reuse conditions are recorded. This inventory only captures the official WMS metadata.",
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(output, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("LAEKEN_ORTHOPHOTO_WMS_DISCOVERY_OK", service_meta)
    for layer in layers:
        print("ORTHO_LAYER", layer["name"], layer["title"], "CRS31370", "EPSG:31370" in layer["crs"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
