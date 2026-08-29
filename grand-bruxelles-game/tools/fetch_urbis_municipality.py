#!/usr/bin/env python3
"""Fetch one official Brussels municipality boundary from UrbIS WFS.

The municipality layer contains only a small number of features, so this tool
fetches the full official layer in EPSG:31370 and performs name matching locally.
That avoids depending on a specific GeoServer property name or CQL schema.

GeoServer-generated top-level feature IDs are deliberately not persisted because
they are transport identifiers and can change between equivalent WFS responses.
Authoritative geometry and properties remain untouched.
"""

from __future__ import annotations

import argparse
import copy
import json
import unicodedata
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

WFS_URL = "https://geoservices-urbis.irisnet.be/geoserver/urbisvector/wfs"
LAYER = "urbisvector:Municipalities"
CRS = "EPSG:31370"
USER_AGENT = "Grand-Bruxelles-Game/1.0 (+https://github.com/Chatnoir01/Chatnoir01)"


def normalize(value: object) -> str:
    text = unicodedata.normalize("NFKD", str(value))
    text = "".join(char for char in text if not unicodedata.combining(char))
    return " ".join(text.casefold().replace("-", " ").split())


def request_all() -> dict[str, Any]:
    params = {
        "service": "WFS",
        "version": "2.0.0",
        "request": "GetFeature",
        "typeNames": LAYER,
        "outputFormat": "application/json",
        "srsName": CRS,
    }
    url = WFS_URL + "?" + urllib.parse.urlencode(params)
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": USER_AGENT,
            "Accept": "application/geo+json, application/json",
        },
    )
    with urllib.request.urlopen(request, timeout=90) as response:
        payload = response.read()
    data = json.loads(payload.decode("utf-8"))
    if data.get("type") != "FeatureCollection":
        raise RuntimeError(f"unexpected WFS payload: {data.get('type')!r}")
    return data


def feature_strings(feature: dict[str, Any]) -> set[str]:
    strings: set[str] = set()
    for value in (feature.get("properties") or {}).values():
        if value is None or isinstance(value, (dict, list)):
            continue
        normalized = normalize(value)
        if normalized:
            strings.add(normalized)
    feature_id = feature.get("id")
    if feature_id:
        strings.add(normalize(feature_id))
    return strings


def select_municipality(data: dict[str, Any], name: str) -> dict[str, Any]:
    target = normalize(name)
    if not target:
        raise ValueError("municipality name cannot be empty")

    exact: list[dict[str, Any]] = []
    partial: list[dict[str, Any]] = []
    for feature in data.get("features", []):
        values = feature_strings(feature)
        if target in values:
            exact.append(feature)
            continue
        if any(target in value or value in target for value in values if len(value) >= 4):
            partial.append(feature)

    candidates = exact or partial
    if len(candidates) == 1:
        return candidates[0]
    if not candidates:
        known = sorted({value for feature in data.get("features", []) for value in feature_strings(feature)})
        raise LookupError(f"municipality {name!r} not found; available property values: {known}")
    raise LookupError(f"municipality {name!r} is ambiguous ({len(candidates)} matches)")


def stable_feature(feature: dict[str, Any]) -> dict[str, Any]:
    """Return versionable GeoJSON without GeoServer's volatile transport ID."""
    result = copy.deepcopy(feature)
    result.pop("id", None)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description="Fetch one official UrbIS municipality polygon")
    parser.add_argument("--name", required=True, help="French or Dutch municipality name")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    data = request_all()
    feature = stable_feature(select_municipality(data, args.name))
    output = {
        "type": "FeatureCollection",
        "name": args.name,
        "crs": {"type": "name", "properties": {"name": CRS}},
        "features": [feature],
        "source": {
            "service": WFS_URL,
            "layer": LAYER,
            "crs": CRS,
        },
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{args.name}: official boundary -> {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
