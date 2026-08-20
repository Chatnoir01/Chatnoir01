#!/usr/bin/env python3
"""Discover the official UrbIS Topo WFS layers needed by Bourse A1.

Evidence only. This does not create runtime geometry and does not infer a curb height.
The target is the source gate left open by bourse_curb_source_policy.game.json:
CR63L road-surface boundary and physical-road-separator line families.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import unicodedata
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

WFS_URL = "https://data.mobility.brussels/geoserver/bm_urbis_topo/wfs"
TARGET_TOPO_TYPES = {
    "CR63L",
    "BR0101L", "BR0102L", "BR0103L", "BR0104L", "BR0105L",
    "BR01L", "BR02L", "BR13L",
}


def _norm(value: str) -> str:
    value = unicodedata.normalize("NFKD", value)
    value = "".join(ch for ch in value if not unicodedata.combining(ch))
    return re.sub(r"[^a-z0-9]+", " ", value.lower()).strip()


def _fetch(url: str) -> tuple[bytes, str]:
    req = urllib.request.Request(url, headers={"User-Agent": "grand-bruxelles-game-source-audit/1.0"})
    with urllib.request.urlopen(req, timeout=45) as response:
        payload = response.read()
    return payload, hashlib.sha256(payload).hexdigest()


def _capabilities() -> tuple[list[dict[str, str]], str, str]:
    query = urllib.parse.urlencode({"service": "WFS", "version": "2.0.0", "request": "GetCapabilities"})
    url = f"{WFS_URL}?{query}"
    payload, digest = _fetch(url)
    root = ET.fromstring(payload)
    records: list[dict[str, str]] = []
    for feature in root.iter():
        if feature.tag.split("}")[-1] != "FeatureType":
            continue
        name = ""
        title = ""
        for child in feature:
            local = child.tag.split("}")[-1]
            if local == "Name":
                name = (child.text or "").strip()
            elif local == "Title":
                title = (child.text or "").strip()
        if name:
            records.append({"name": name, "title": title})
    return records, digest, url


def _is_candidate(record: dict[str, str]) -> bool:
    text = _norm(f"{record.get('name','')} {record.get('title','')}")
    families = (
        "revetement routier limite",
        "limite revetement",
        "road surface limit",
        "road surface boundary",
        "separateur physique de chaussee",
        "physical road separator",
        "road separator",
    )
    return any(term in text for term in families)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    feature_types, cap_sha, cap_url = _capabilities()
    candidates = [record for record in feature_types if _is_candidate(record)]
    if not candidates:
        # Keep the complete advertised list in the evidence artifact so the next
        # revision can resolve a naming mismatch without guessing a runtime layer.
        print("BOURSE_A1_CURB_LAYER_DISCOVERY_FAIL: no title/name candidate found")

    result = {
        "schema": "grand-bruxelles-bourse-a1-curb-layer-discovery-v1",
        "publisher": "Brussels Mobility / Paradigm",
        "workspace": "bm_urbis_topo",
        "wfs_url": WFS_URL,
        "capabilities_url": cap_url,
        "capabilities_sha256": cap_sha,
        "advertised_feature_type_count": len(feature_types),
        "target_topo_types": sorted(TARGET_TOPO_TYPES),
        "candidate_feature_types": candidates,
        "all_feature_types": feature_types,
        "physical_curb_height_supported": False,
        "vertical_extrusion_allowed": False,
        "runtime_approved": False,
        "realism_complete": False,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(
        "BOURSE_A1_CURB_LAYER_DISCOVERY",
        f"advertised={len(feature_types)}",
        f"candidates={len(candidates)}",
        f"capabilities_sha256={cap_sha}",
    )
    for record in candidates:
        print("BOURSE_A1_CURB_LAYER_CANDIDATE", json.dumps(record, ensure_ascii=False))
    if not candidates:
        raise SystemExit(1)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
