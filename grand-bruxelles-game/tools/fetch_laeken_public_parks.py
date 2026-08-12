#!/usr/bin/env python3
"""Fetch City of Brussels public parks/gardens intersecting the Laeken phase bbox."""

from __future__ import annotations

import hashlib
import json
import urllib.parse
import urllib.request
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

DATASET_ID = "parcs_et_jardins_publics"
EXPORT_BASE = (
    "https://bruxellesdata.opendatasoft.com/api/explore/v2.1/catalog/datasets/"
    f"{DATASET_ID}/exports/geojson"
)
BBOX = (147300.0, 173650.0, 149100.0, 176750.0)
ORIGIN_E = 147868.29422791934
ORIGIN_N = 169538.62414926197
OUTPUT = Path("data/environment/laeken_jette/official_public_parks.game.json")
PROVENANCE = Path("data/sources/laeken_jette/official_public_parks_provenance.json")
USER_AGENT = "Grand-Bruxelles-Game/1.0 (official City public parks import)"


def fetch() -> tuple[bytes, str]:
    params = {"lang": "fr", "timezone": "Europe/Brussels", "use_labels": "false", "epsg": "31370"}
    url = EXPORT_BASE + "?" + urllib.parse.urlencode(params)
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read(), url


def iter_positions(value):
    if isinstance(value, list):
        if len(value) >= 2 and isinstance(value[0], (int, float)) and isinstance(value[1], (int, float)):
            yield float(value[0]), float(value[1])
        else:
            for child in value:
                yield from iter_positions(child)


def geometry_intersects_bbox(geometry: dict) -> bool:
    points = list(iter_positions(geometry.get("coordinates", [])))
    if not points:
        return False
    min_e, min_n, max_e, max_n = BBOX
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    return max(xs) >= min_e and min(xs) <= max_e and max(ys) >= min_n and min(ys) <= max_n


def convert_coordinates(value):
    if isinstance(value, list):
        if len(value) >= 2 and isinstance(value[0], (int, float)) and isinstance(value[1], (int, float)):
            converted = [float(value[0]) - ORIGIN_E, -(float(value[1]) - ORIGIN_N)]
            if len(value) > 2:
                converted.extend(value[2:])
            return converted
        return [convert_coordinates(child) for child in value]
    return value


def scalar(value):
    if value is None or isinstance(value, (str, int, float, bool)):
        return value
    return json.dumps(value, ensure_ascii=False, sort_keys=True)


def main() -> int:
    raw, url = fetch()
    source_sha = hashlib.sha256(raw).hexdigest()
    document = json.loads(raw.decode("utf-8"))
    source_features = document.get("features", [])
    selected = []
    geometry_counts = Counter()
    names = []

    for index, feature in enumerate(source_features):
        if not isinstance(feature, dict):
            continue
        geometry = feature.get("geometry")
        if not isinstance(geometry, dict) or not geometry_intersects_bbox(geometry):
            continue
        kind = str(geometry.get("type") or "")
        geometry_counts[kind] += 1
        props = feature.get("properties") or {}
        if not isinstance(props, dict):
            props = {}
        name = props.get("name_fr") or props.get("name") or props.get("nom") or props.get("title_fr")
        if name:
            names.append(str(name))
        selected.append({
            "type": "Feature",
            "id": str(feature.get("id") or f"park-{index}"),
            "geometry": {"type": kind, "coordinates": convert_coordinates(geometry.get("coordinates", []))},
            "properties": {key: scalar(value) for key, value in props.items()},
        })

    output = {
        "type": "FeatureCollection",
        "name": "Laeken official public parks and gardens",
        "features": selected,
        "grand_bruxelles_coordinate_system": {
            "source_crs": "EPSG:31370",
            "origin_e": ORIGIN_E,
            "origin_n": ORIGIN_N,
            "axes": "X=east, Y=up, Z=south",
            "units": "metres",
        },
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(output, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")

    provenance = {
        "schema": 1,
        "dataset_id": DATASET_ID,
        "publisher": "Ville de Bruxelles / City of Brussels Open Data",
        "license": "CC BY 4.0",
        "license_url": "https://creativecommons.org/licenses/by/4.0/",
        "source_url": url,
        "source_crs": "EPSG:31370",
        "bbox_epsg31370": list(BBOX),
        "fetched_at_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "source_sha256": source_sha,
        "source_feature_count": len(source_features),
        "selected_feature_count": len(selected),
        "geometry_type_counts": dict(geometry_counts),
        "selected_names": sorted(set(names)),
        "visual_policy": "Official park geometry may guide subtle ground/vegetation treatment. It must not replace the georeferenced orthophoto or invent park furniture not present in another source.",
    }
    PROVENANCE.parent.mkdir(parents=True, exist_ok=True)
    PROVENANCE.write_text(json.dumps(provenance, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    if not selected:
        raise SystemExit("No public park/garden geometry intersects Laeken phase bbox")
    print("LAEKEN_PUBLIC_PARKS_OK", len(source_features), len(selected), dict(geometry_counts), sorted(set(names)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
