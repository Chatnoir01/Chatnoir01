#!/usr/bin/env python3
"""Normalize the STIB-MIVB datasets that are actually proven by the current open-data intake.

This stage consumes the published GTFS Stops export plus the published commercial-network
geometry export. It deliberately does not manufacture a complete GTFS schedule and performs
no project-coordinate reprojection.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
from typing import Any

FORMAT = "grand-bruxelles-stib-open-data-surface-v1"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def ci_get(props: dict[str, Any], *keys: str) -> Any:
    index = {str(k).lower(): v for k, v in props.items()}
    for key in keys:
        value = index.get(key.lower())
        if value not in (None, ""):
            return value
    return None


def finite(value: Any) -> float | None:
    try:
        result = float(value)
    except (TypeError, ValueError):
        return None
    return result if math.isfinite(result) else None


def load_rows(path: Path) -> list[dict[str, Any]]:
    suffix = path.suffix.lower()
    if suffix == ".csv":
        with path.open("r", encoding="utf-8-sig", newline="") as handle:
            return [dict(row) for row in csv.DictReader(handle)]
    value = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(value, list):
        return [row for row in value if isinstance(row, dict)]
    if isinstance(value, dict):
        if value.get("type") == "FeatureCollection" and isinstance(value.get("features"), list):
            return [row for row in value["features"] if isinstance(row, dict)]
        for key in ("results", "records", "data"):
            rows = value.get(key)
            if isinstance(rows, list):
                return [row for row in rows if isinstance(row, dict)]
    raise SystemExit(f"unsupported STIB export structure: {path}")


def props_and_geometry(row: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any] | None, str | None]:
    if row.get("type") == "Feature":
        props = row.get("properties") if isinstance(row.get("properties"), dict) else {}
        geometry = row.get("geometry") if isinstance(row.get("geometry"), dict) else None
        feature_id = None if row.get("id") in (None, "") else str(row.get("id"))
        return props, geometry, feature_id
    geometry = None
    for key in ("geometry", "geo_shape", "geoshape"):
        candidate = row.get(key)
        if isinstance(candidate, dict) and isinstance(candidate.get("type"), str):
            geometry = candidate
            break
    return row, geometry, None


def point_wgs84(props: dict[str, Any], geometry: dict[str, Any] | None) -> list[float] | None:
    if isinstance(geometry, dict) and geometry.get("type") == "Point":
        coords = geometry.get("coordinates")
        if isinstance(coords, list) and len(coords) >= 2:
            lon = finite(coords[0]); lat = finite(coords[1])
            if lon is not None and lat is not None and -180 <= lon <= 180 and -90 <= lat <= 90:
                return [round(lon, 7), round(lat, 7)]
    lon = finite(ci_get(props, "stop_lon", "longitude", "lon"))
    lat = finite(ci_get(props, "stop_lat", "latitude", "lat"))
    if lon is not None and lat is not None and -180 <= lon <= 180 and -90 <= lat <= 90:
        return [round(lon, 7), round(lat, 7)]
    return None


def normalize_stops(rows: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], int]:
    normalized: list[dict[str, Any]] = []
    rejected = 0
    for row in rows:
        props, geometry, feature_id = props_and_geometry(row)
        stop_id_raw = ci_get(props, "stop_id", "stopid")
        name_raw = ci_get(props, "stop_name", "stopname", "name")
        stop_id = str(stop_id_raw).strip() if stop_id_raw not in (None, "") else (feature_id or "")
        name = str(name_raw).strip() if name_raw not in (None, "") else ""
        wgs84 = point_wgs84(props, geometry)
        if not stop_id or not name or wgs84 is None:
            rejected += 1
            continue
        normalized.append({
            "stop_id": stop_id,
            "name": name,
            "wgs84": wgs84,
            "source_properties": props,
        })
    normalized.sort(key=lambda row: row["stop_id"])
    return normalized, rejected


def normalize_network(rows: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], int]:
    allowed = {"Point", "MultiPoint", "LineString", "MultiLineString"}
    normalized: list[dict[str, Any]] = []
    rejected = 0
    for index, row in enumerate(rows):
        props, geometry, feature_id = props_and_geometry(row)
        if not isinstance(geometry, dict) or geometry.get("type") not in allowed or "coordinates" not in geometry:
            rejected += 1
            continue
        stable_id = feature_id or str(ci_get(props, "id", "objectid", "fid") or f"source-index-{index}")
        normalized.append({
            "source_feature_id": stable_id,
            "geometry": geometry,
            "source_properties": props,
        })
    normalized.sort(key=lambda row: row["source_feature_id"])
    return normalized, rejected


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--stops", type=Path, required=True)
    parser.add_argument("--network-shapes", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--license", required=True)
    parser.add_argument("--min-stops", type=int, default=1)
    parser.add_argument("--min-network-features", type=int, default=1)
    args = parser.parse_args()

    stop_rows = load_rows(args.stops)
    network_rows = load_rows(args.network_shapes)
    stops, rejected_stops = normalize_stops(stop_rows)
    network, rejected_network = normalize_network(network_rows)
    if len(stops) < args.min_stops:
        raise SystemExit(f"STIB stops gate failed: {len(stops)} < {args.min_stops}")
    if len(network) < args.min_network_features:
        raise SystemExit(f"STIB commercial-network gate failed: {len(network)} < {args.min_network_features}")

    output = {
        "format": FORMAT,
        "source": {
            "publisher": "STIB-MIVB",
            "license": args.license,
            "stops_dataset": "gtfs-stops-production",
            "network_dataset": "shapefiles-production",
            "stops_sha256": sha256_file(args.stops),
            "network_sha256": sha256_file(args.network_shapes),
            "stops_coordinate_reference": "GTFS stop coordinates / WGS84",
            "network_coordinate_reference": "source export preserved; no reprojection performed in this stage",
        },
        "stats": {
            "source_stop_row_count": len(stop_rows),
            "normalized_stop_count": len(stops),
            "rejected_stop_count": rejected_stops,
            "source_network_row_count": len(network_rows),
            "normalized_network_feature_count": len(network),
            "rejected_network_feature_count": rejected_network,
        },
        "stops": stops,
        "commercial_network": network,
        "runtime_authorized": False,
        "production_authorized": False,
        "semantic_rules": [
            "Only the two currently proven STIB open-data products are normalized here.",
            "No routes.txt, trips.txt or schedule semantics are fabricated.",
            "Commercial-network source properties are preserved instead of guessed into GTFS route fields.",
            "No source geometry is reprojected or moved in this stage.",
            "Existing STIB runtime/visual owners retain ownership."
        ]
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        f"STIB_OPEN_DATA_NORMALIZATION_OK: {len(stops)} stops, "
        f"{len(network)} commercial-network features -> {args.output}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
