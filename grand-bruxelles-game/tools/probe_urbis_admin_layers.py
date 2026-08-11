#!/usr/bin/env python3
"""Probe discovered UrbIS admin layers for required Brussels City subzones.

A candidate layer is useful only if its real feature attributes identify the
places needed by this workstream. To avoid blindly downloading huge datasets,
we first issue a WFS 2.0 resultType=hits request. Layers above the configurable
feature limit are recorded as skipped rather than fetched.
"""

from __future__ import annotations

import argparse
import json
import re
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any

WFS_URL = "https://geoservices-urbis.irisnet.be/geoserver/urbisvector/wfs"
DISCOVERY_FORMAT = "grand-bruxelles-urbis-admin-layer-discovery-v1"
FORMAT = "grand-bruxelles-urbis-admin-layer-probe-v1"
DEFAULT_TARGETS = ("haren", "neder-over-heembeek")


def normalized(value: object) -> str:
    text = str(value or "").casefold()
    text = re.sub(r"[^a-z0-9]+", " ", text)
    return " ".join(text.split())


def target_forms(target: str) -> set[str]:
    base = normalized(target)
    compact = base.replace(" ", "")
    return {base, compact}


def value_matches(value: object, target: str) -> bool:
    candidate = normalized(value)
    candidate_compact = candidate.replace(" ", "")
    return any(form and (form in candidate or form in candidate_compact) for form in target_forms(target))


def matching_properties(properties: dict[str, Any], target: str) -> dict[str, str]:
    return {
        str(key): str(value)
        for key, value in properties.items()
        if isinstance(value, (str, int, float)) and value_matches(value, target)
    }


def request_bytes(params: dict[str, str], timeout: int = 90) -> bytes:
    url = WFS_URL + "?" + urllib.parse.urlencode(params)
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": "Grand-Bruxelles-Game/1.0 (+https://github.com/Chatnoir01/Chatnoir01)",
            "Accept": "application/json,application/xml,text/xml;q=0.9,*/*;q=0.1",
        },
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read()


def feature_count(layer_name: str) -> int | None:
    payload = request_bytes(
        {
            "service": "WFS",
            "version": "2.0.0",
            "request": "GetFeature",
            "typeNames": layer_name,
            "resultType": "hits",
        }
    )
    root = ET.fromstring(payload)
    raw = root.attrib.get("numberMatched") or root.attrib.get("numberOfFeatures")
    if raw is None or raw == "unknown":
        return None
    return int(raw)


def fetch_features(layer_name: str) -> dict[str, Any]:
    payload = request_bytes(
        {
            "service": "WFS",
            "version": "2.0.0",
            "request": "GetFeature",
            "typeNames": layer_name,
            "outputFormat": "application/json",
            "srsName": "EPSG:31370",
        }
    )
    data = json.loads(payload.decode("utf-8"))
    if data.get("type") != "FeatureCollection":
        raise ValueError(f"unexpected WFS payload for {layer_name}: {data.get('type')!r}")
    return data


def geometry_bbox(geometry: dict[str, Any] | None) -> list[float] | None:
    if not geometry:
        return None
    positions: list[tuple[float, float]] = []

    def walk(value: object) -> None:
        if not isinstance(value, list):
            return
        if len(value) >= 2 and isinstance(value[0], (int, float)) and isinstance(value[1], (int, float)):
            positions.append((float(value[0]), float(value[1])))
            return
        for child in value:
            walk(child)

    walk(geometry.get("coordinates"))
    if not positions:
        return None
    return [
        min(point[0] for point in positions),
        min(point[1] for point in positions),
        max(point[0] for point in positions),
        max(point[1] for point in positions),
    ]


def inspect_document(layer_name: str, document: dict[str, Any], targets: list[str]) -> dict[str, Any]:
    matches: dict[str, list[dict[str, Any]]] = {target: [] for target in targets}
    for feature in document.get("features", []):
        if not isinstance(feature, dict):
            continue
        properties = feature.get("properties") or {}
        if not isinstance(properties, dict):
            continue
        for target in targets:
            props = matching_properties(properties, target)
            if not props:
                continue
            matches[target].append(
                {
                    "feature_id": str(feature.get("id") or properties.get("INSPIRE_ID") or ""),
                    "matching_properties": props,
                    "geometry_type": str((feature.get("geometry") or {}).get("type") or ""),
                    "geometry_bbox": geometry_bbox(feature.get("geometry")),
                }
            )
    return {
        "layer": layer_name,
        "feature_count_downloaded": len(document.get("features", [])),
        "target_matches": matches,
        "matched_targets": [target for target in targets if matches[target]],
    }


def load_candidates(path: Path) -> list[dict[str, Any]]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("format") != DISCOVERY_FORMAT:
        raise ValueError(f"unsupported discovery format: {path}")
    candidates = payload.get("candidates")
    if not isinstance(candidates, list):
        raise ValueError("discovery manifest has no candidates list")
    return [candidate for candidate in candidates if isinstance(candidate, dict) and candidate.get("name")]


def main() -> int:
    parser = argparse.ArgumentParser(description="Probe official UrbIS admin candidates for Brussels City subzone names")
    parser.add_argument("--discovery", type=Path, required=True)
    parser.add_argument("--target", action="append", default=[])
    parser.add_argument("--max-features", type=int, default=2500)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    targets = args.target or list(DEFAULT_TARGETS)
    results: list[dict[str, Any]] = []
    for candidate in load_candidates(args.discovery):
        layer_name = str(candidate["name"])
        count = feature_count(layer_name)
        entry: dict[str, Any] = {
            "layer": layer_name,
            "title": str(candidate.get("title", "")),
            "number_matched": count,
            "status": "pending",
        }
        if count is None:
            entry["status"] = "skipped_unknown_feature_count"
        elif count > args.max_features:
            entry["status"] = "skipped_feature_limit"
        else:
            document = fetch_features(layer_name)
            entry.update(inspect_document(layer_name, document, targets))
            entry["status"] = "inspected"
        results.append(entry)
        print(f"{layer_name}: {entry['status']} count={count} matched={entry.get('matched_targets', [])}")

    proven = [
        entry["layer"]
        for entry in results
        if entry.get("status") == "inspected"
        and all(target in entry.get("matched_targets", []) for target in targets)
    ]
    output = {
        "format": FORMAT,
        "source": WFS_URL,
        "targets": targets,
        "max_features": args.max_features,
        "candidate_count": len(results),
        "proven_layers_matching_all_targets": proven,
        "production_approved_layer": None,
        "production_gate": "manual/schema/geometric validation still required after attribute-name proof",
        "results": results,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"probe -> {args.output}; proven attribute layers={proven}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
