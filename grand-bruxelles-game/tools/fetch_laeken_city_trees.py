#!/usr/bin/env python3
"""Fetch official public-tree positions for the Laeken/Heysel phase bbox.

Source: City of Brussels Open Data dataset `arbres-bomen-vbx-be-bm`, which
aggregates trees managed by the City, Brussels Environment and Brussels Mobility
within City of Brussels territory. The catalogue publishes it under CC BY 4.0.

The OpenDataSoft export is requested directly in EPSG:31370 so filtering and
conversion use the exact same Lambert 72 frame as the rest of Grand Bruxelles.
The source inventory is explicitly incomplete; these records are authoritative
known tree positions, not a claim that every tree in Laeken is represented.
"""

from __future__ import annotations

import hashlib
import json
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

DATASET_ID = "arbres-bomen-vbx-be-bm"
EXPORT_BASE = (
    "https://bruxellesdata.opendatasoft.com/api/explore/v2.1/catalog/datasets/"
    f"{DATASET_ID}/exports/geojson"
)
BBOX = (147300.0, 173650.0, 149100.0, 176750.0)
ORIGIN_E = 147868.29422791934
ORIGIN_N = 169538.62414926197
OUTPUT = Path("data/environment/laeken_jette/official_city_trees.game.json")
PROVENANCE = Path("data/sources/laeken_jette/official_city_trees_provenance.json")
USER_AGENT = "Grand-Bruxelles-Game/1.0 (official City of Brussels trees import)"


def fetch() -> tuple[bytes, str]:
    params = {
        "lang": "fr",
        "timezone": "Europe/Brussels",
        "use_labels": "false",
        "epsg": "31370",
    }
    url = EXPORT_BASE + "?" + urllib.parse.urlencode(params)
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read(), url


def point_from_geometry(geometry: object) -> tuple[float, float] | None:
    if not isinstance(geometry, dict) or geometry.get("type") != "Point":
        return None
    coords = geometry.get("coordinates")
    if not isinstance(coords, list) or len(coords) < 2:
        return None
    try:
        return float(coords[0]), float(coords[1])
    except (TypeError, ValueError):
        return None


def in_bbox(east: float, north: float) -> bool:
    min_e, min_n, max_e, max_n = BBOX
    return min_e <= east <= max_e and min_n <= north <= max_n


def stable_record_id(properties: dict, east: float, north: float) -> str:
    for key in ("id", "be_id_tree_be", "bm_id_number"):
        value = properties.get(key)
        if value not in (None, ""):
            return str(value)
    return "tree-%s" % hashlib.sha1(f"{east:.3f},{north:.3f}".encode()).hexdigest()[:16]


def main() -> int:
    raw, url = fetch()
    source_sha = hashlib.sha256(raw).hexdigest()
    document = json.loads(raw.decode("utf-8"))
    if document.get("type") != "FeatureCollection":
        raise SystemExit("Tree export is not a GeoJSON FeatureCollection")

    source_features = document.get("features", [])
    selected = []
    source_counts: dict[str, int] = {}
    territory_counts: dict[str, int] = {}
    district_counts: dict[str, int] = {}
    species_counts: dict[str, int] = {}

    for feature in source_features:
        if not isinstance(feature, dict):
            continue
        point = point_from_geometry(feature.get("geometry"))
        if point is None:
            continue
        east, north = point
        if not in_bbox(east, north):
            continue
        props = feature.get("properties") or {}
        if not isinstance(props, dict):
            props = {}
        source = str(props.get("source_fr") or props.get("source_nl") or "non renseigné")
        territory = str(props.get("territory_fr") or props.get("territory_nl") or "non renseigné")
        district = str(props.get("district_fr") or props.get("district_nl") or "non renseigné")
        species = str(props.get("species") or "non renseignée")
        source_counts[source] = source_counts.get(source, 0) + 1
        territory_counts[territory] = territory_counts.get(territory, 0) + 1
        district_counts[district] = district_counts.get(district, 0) + 1
        species_counts[species] = species_counts.get(species, 0) + 1

        selected.append({
            "type": "Feature",
            "id": stable_record_id(props, east, north),
            "geometry": {
                "type": "Point",
                "coordinates": [east - ORIGIN_E, -(north - ORIGIN_N)],
            },
            "properties": {
                "species": props.get("species"),
                "source_fr": props.get("source_fr"),
                "territory_fr": props.get("territory_fr"),
                "district_fr": props.get("district_fr"),
                "address_fr": props.get("address_fr"),
                "date_refreshed": props.get("date_refreshed"),
                "source_east_m": round(east, 3),
                "source_north_m": round(north, 3),
            },
        })

    output = {
        "type": "FeatureCollection",
        "name": "Laeken/Jette official known public trees",
        "features": selected,
        "grand_bruxelles_coordinate_system": {
            "source_crs": "EPSG:31370",
            "origin_e": ORIGIN_E,
            "origin_n": ORIGIN_N,
            "axes": "X=east, Y=up, Z=south",
            "units": "metres",
        },
        "source_note": "Known public-tree inventory only; source catalogue states the inventory is still being completed.",
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(output, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")

    provenance = {
        "schema": 1,
        "dataset_id": DATASET_ID,
        "publisher": "Ville de Bruxelles / City of Brussels Open Data",
        "contributors": ["Ville de Bruxelles", "Bruxelles Environnement", "Bruxelles Mobilité"],
        "license": "CC BY 4.0",
        "license_url": "https://creativecommons.org/licenses/by/4.0/",
        "source_url": url,
        "source_crs": "EPSG:31370",
        "bbox_epsg31370": list(BBOX),
        "fetched_at_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "source_sha256": source_sha,
        "source_feature_count": len(source_features),
        "selected_feature_count": len(selected),
        "source_counts": source_counts,
        "territory_counts": territory_counts,
        "district_counts": district_counts,
        "species_distinct": len(species_counts),
        "top_species": sorted(species_counts.items(), key=lambda item: (-item[1], item[0]))[:30],
        "completeness_warning": "The source catalogue says public actors are still completing the inventory and updates can lag field changes.",
        "visual_policy": "Positions and species are source-grounded. Tree mesh shape/size is a deterministic visual approximation unless dimensional fields are present in a future source revision.",
    }
    PROVENANCE.parent.mkdir(parents=True, exist_ok=True)
    PROVENANCE.write_text(json.dumps(provenance, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    if len(selected) < 100:
        raise SystemExit(f"Unexpectedly few trees inside Laeken bbox: {len(selected)}")
    print("LAEKEN_OFFICIAL_TREES_OK", {
        "source": len(source_features),
        "selected": len(selected),
        "species": len(species_counts),
        "sha256": source_sha,
    })
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
