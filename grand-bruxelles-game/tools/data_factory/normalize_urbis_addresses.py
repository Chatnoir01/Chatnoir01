#!/usr/bin/env python3
"""Normalize official UrbIS AddressNumbers into a deterministic data-only registry.

No building identity is inferred. Source IDs/properties remain traceable and the output is
not runtime-authorized.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from typing import Any

ORIGIN_E = 147868.29422791934
ORIGIN_N = 169538.62414926197
FORMAT = "grand-bruxelles-urbis-address-registry-v1"


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def load_geojson(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict) or value.get("type") != "FeatureCollection" or not isinstance(value.get("features"), list):
        raise SystemExit(f"invalid GeoJSON FeatureCollection: {path}")
    return value


def ci_get(props: dict[str, Any], *keys: str) -> Any:
    index = {str(k).lower(): v for k, v in props.items()}
    for key in keys:
        value = index.get(key.lower())
        if value not in (None, ""):
            return value
    return None


def clean_text(value: Any) -> str | None:
    if value in (None, ""):
        return None
    text = str(value).strip()
    return text or None


def finite_xy(feature: dict[str, Any]) -> tuple[float, float] | None:
    geom = feature.get("geometry")
    if not isinstance(geom, dict) or geom.get("type") != "Point":
        return None
    coords = geom.get("coordinates")
    if not isinstance(coords, list) or len(coords) < 2:
        return None
    try:
        x, y = float(coords[0]), float(coords[1])
    except (TypeError, ValueError):
        return None
    if not (math.isfinite(x) and math.isfinite(y)):
        return None
    if not (0.0 < x < 1_000_000.0 and 0.0 < y < 1_000_000.0):
        return None
    return x, y


def game_xz(east: float, north: float) -> list[float]:
    return [round(east - ORIGIN_E, 3), round(-(north - ORIGIN_N), 3)]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--address-numbers", type=Path, required=True)
    parser.add_argument("--addresses", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--license", default="UrbIS / verify upstream intake metadata")
    parser.add_argument("--min-records", type=int, default=1)
    args = parser.parse_args()

    numbers_doc = load_geojson(args.address_numbers)
    records: list[dict[str, Any]] = []
    rejected_non_point = 0

    for feature in numbers_doc["features"]:
        if not isinstance(feature, dict):
            continue
        xy = finite_xy(feature)
        if xy is None:
            rejected_non_point += 1
            continue
        props = feature.get("properties") if isinstance(feature.get("properties"), dict) else {}
        source_id = clean_text(ci_get(props, "INSPIRE_ID", "ID", "OBJECTID")) or clean_text(feature.get("id"))
        east, north = xy
        records.append({
            "source_id": source_id,
            "street_name_fr": clean_text(ci_get(props, "STRNAMEFRE", "STREETNAMEFRE", "STREET_FR")),
            "street_name_nl": clean_text(ci_get(props, "STRNAMEDUT", "STRNAMENL", "STREETNAMEDUT", "STREET_NL")),
            "house_number": clean_text(ci_get(props, "POLICENUM", "HOUSENUMBER", "HOUSE_NUMBER", "NUMBER")),
            "municipality_fr": clean_text(ci_get(props, "MUNNAMEFRE", "MUNICIPALITYFRE", "MUNICIPALITY_FR")),
            "municipality_nl": clean_text(ci_get(props, "MUNNAMEDUT", "MUNNAMENL", "MUNICIPALITY_NL")),
            "postal_code": clean_text(ci_get(props, "POSTCODE", "POSTALCODE", "ZIP", "ZIPCODE")),
            "lambert72": [round(east, 3), round(north, 3)],
            "game_xz": game_xz(east, north),
            "source_properties": props,
        })

    records.sort(key=lambda r: (
        str(r.get("source_id") or ""),
        str(r.get("municipality_fr") or r.get("municipality_nl") or ""),
        str(r.get("street_name_fr") or r.get("street_name_nl") or ""),
        str(r.get("house_number") or ""),
        r["lambert72"][0],
        r["lambert72"][1],
    ))
    if len(records) < args.min_records:
        raise SystemExit(f"UrbIS address normalization gate failed: {len(records)} < {args.min_records}")

    addresses_meta: dict[str, Any] | None = None
    if args.addresses:
        address_doc = load_geojson(args.addresses)
        addresses_meta = {
            "path": str(args.addresses),
            "sha256": sha256_file(args.addresses),
            "feature_count": len(address_doc["features"]),
            "role": "secondary official address layer retained for later exact reconciliation; no guessed join in this stage",
        }

    output = {
        "format": FORMAT,
        "source": {
            "publisher": "Paradigm / UrbIS",
            "layer": "urbisvector:AddressNumbers",
            "crs": "EPSG:31370",
            "license": args.license,
            "address_numbers_sha256": sha256_file(args.address_numbers),
            "addresses_layer": addresses_meta,
        },
        "coordinate_system": {
            "source_crs": "EPSG:31370",
            "origin_e": ORIGIN_E,
            "origin_n": ORIGIN_N,
            "game_axes": "X=east, Z=south",
            "units": "metres",
        },
        "stats": {
            "source_feature_count": len(numbers_doc["features"]),
            "normalized_record_count": len(records),
            "rejected_non_point_or_invalid_coordinate_count": rejected_non_point,
        },
        "records": records,
        "runtime_authorized": False,
        "production_authorized": False,
        "semantic_rules": [
            "No nearest-neighbour building identity is inferred.",
            "BeSt Address may cross-check this registry but may not silently overwrite it.",
            "Unknown or conflicting identities remain HOLD until explicit reconciliation."
        ],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"URBIS_ADDRESS_NORMALIZATION_OK: {len(records)} records -> {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
