#!/usr/bin/env python3
"""Fetch full ISO metadata for the official Geobru DSM and LiDAR datasets."""

from __future__ import annotations

import json
import re
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path

CSW = "https://geobru.irisnet.be/geonetwork/srv/eng/csw"
OUTPUT = Path("data/sources/laeken_jette/geobru_height_metadata.json")
USER_AGENT = "Grand-Bruxelles-Game/1.0 (official DSM/LiDAR metadata fetch)"
DATASETS = {
    "dsm": "8c2d921e-6a53-11ed-bfb5-010101010000",
    "lidar_2021": "ff1124e1-424e-11ee-b156-00090ffe0001",
}

NS = {
    "gmd": "http://www.isotc211.org/2005/gmd",
    "gco": "http://www.isotc211.org/2005/gco",
    "gmx": "http://www.isotc211.org/2005/gmx",
    "srv": "http://www.isotc211.org/2005/srv",
    "gml": "http://www.opengis.net/gml",
    "xlink": "http://www.w3.org/1999/xlink",
}


def fetch_metadata(identifier: str) -> tuple[bytes, str]:
    params = {
        "service": "CSW",
        "version": "2.0.2",
        "request": "GetRecordById",
        "elementSetName": "full",
        "outputSchema": "http://www.isotc211.org/2005/gmd",
        "id": identifier,
    }
    url = CSW + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=60) as response:
        return response.read(), url


def all_text(node: ET.Element | None) -> str:
    if node is None:
        return ""
    values = []
    for descendant in node.iter():
        text = (descendant.text or "").strip()
        if text:
            values.append(text)
    return " ".join(values)


def first_text(root: ET.Element, xpath: str) -> str | None:
    node = root.find(xpath, NS)
    text = all_text(node).strip() if node is not None else ""
    return text or None


def extract_online_resources(root: ET.Element) -> list[dict]:
    resources = []
    for online in root.findall(".//gmd:CI_OnlineResource", NS):
        linkage = first_text(online, "gmd:linkage")
        protocol = first_text(online, "gmd:protocol")
        name = first_text(online, "gmd:name")
        description = first_text(online, "gmd:description")
        function = first_text(online, "gmd:function")
        if linkage:
            resources.append({
                "url": linkage,
                "protocol": protocol,
                "name": name,
                "description": description,
                "function": function,
            })
    # Some metadata stores links directly in gmx:Anchor xlink:href.
    for anchor in root.findall(".//gmx:Anchor", NS):
        href = anchor.attrib.get("{%s}href" % NS["xlink"])
        if href and href.startswith(("http://", "https://")):
            if not any(item["url"] == href for item in resources):
                resources.append({
                    "url": href,
                    "protocol": None,
                    "name": (anchor.text or "").strip() or None,
                    "description": "gmx:Anchor",
                    "function": None,
                })
    return resources


def extract_constraints(root: ET.Element) -> dict:
    use_limitations = []
    access_constraints = []
    use_constraints = []
    other_constraints = []
    for node in root.findall(".//gmd:MD_LegalConstraints", NS):
        for value in node.findall("gmd:useLimitation", NS):
            text = all_text(value).strip()
            if text:
                use_limitations.append(text)
        for value in node.findall("gmd:accessConstraints", NS):
            text = all_text(value).strip()
            if text:
                access_constraints.append(text)
        for value in node.findall("gmd:useConstraints", NS):
            text = all_text(value).strip()
            if text:
                use_constraints.append(text)
        for value in node.findall("gmd:otherConstraints", NS):
            text = all_text(value).strip()
            if text:
                other_constraints.append(text)
    return {
        "use_limitations": sorted(set(use_limitations)),
        "access_constraints": sorted(set(access_constraints)),
        "use_constraints": sorted(set(use_constraints)),
        "other_constraints": sorted(set(other_constraints)),
    }


def extract_reference_systems(root: ET.Element) -> list[str]:
    values = []
    for ref in root.findall(".//gmd:referenceSystemInfo", NS):
        text = all_text(ref).strip()
        if text:
            values.append(text)
    return sorted(set(values))


def extract_bbox(root: ET.Element) -> list[dict]:
    boxes = []
    for box in root.findall(".//gmd:EX_GeographicBoundingBox", NS):
        def number(name: str):
            node = box.find(f"gmd:{name}", NS)
            text = all_text(node).strip() if node is not None else ""
            try:
                return float(text)
            except ValueError:
                return None
        boxes.append({
            "west": number("westBoundLongitude"),
            "east": number("eastBoundLongitude"),
            "south": number("southBoundLatitude"),
            "north": number("northBoundLatitude"),
        })
    return boxes


def main() -> int:
    output = {
        "schema": 1,
        "source": "Geobru official GeoNetwork CSW",
        "csw_endpoint": CSW,
        "fetched_at_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "datasets": {},
        "policy": "Only official online resources and legal constraints from ISO metadata are recorded. Height extraction is enabled only after a downloadable metric DSM/LiDAR source and compatible CRS are confirmed.",
    }

    for key, identifier in DATASETS.items():
        raw, request_url = fetch_metadata(identifier)
        root = ET.fromstring(raw)
        title = first_text(root, ".//gmd:citation//gmd:title")
        abstract = first_text(root, ".//gmd:abstract")
        date_stamp = first_text(root, ".//gmd:dateStamp")
        resources = extract_online_resources(root)
        output["datasets"][key] = {
            "identifier": identifier,
            "request_url": request_url,
            "metadata_bytes": len(raw),
            "title": title,
            "abstract": abstract,
            "date_stamp": date_stamp,
            "reference_systems": extract_reference_systems(root),
            "geographic_bounding_boxes": extract_bbox(root),
            "legal_constraints": extract_constraints(root),
            "online_resources": resources,
        }
        print("GEOBRU_HEIGHT_METADATA", key, title, "resources", len(resources))
        for resource in resources:
            print("RESOURCE", key, resource)

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(output, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
