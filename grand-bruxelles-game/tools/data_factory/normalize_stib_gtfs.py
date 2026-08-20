#!/usr/bin/env python3
"""Normalize STIB-MIVB static GTFS into a deterministic data-only registry.

The tool preserves producer IDs and route colours and never grants runtime authorization.
GTFS latitude/longitude remain WGS84 at this stage; project-coordinate projection is a later,
separately validated step.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import math
import zipfile
from pathlib import Path
from typing import Any

FORMAT = "grand-bruxelles-stib-static-v1"
REQUIRED = ("stops.txt", "routes.txt")


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def text_rows(raw: bytes) -> list[dict[str, str]]:
    text = raw.decode("utf-8-sig")
    return [dict(row) for row in csv.DictReader(io.StringIO(text))]


def load_tables(path: Path) -> tuple[dict[str, list[dict[str, str]]], dict[str, str]]:
    tables: dict[str, list[dict[str, str]]] = {}
    hashes: dict[str, str] = {}
    names = ("stops.txt", "routes.txt", "trips.txt", "shapes.txt", "agency.txt", "calendar.txt", "calendar_dates.txt")
    if path.is_dir():
        for name in names:
            p = path / name
            if p.is_file():
                raw = p.read_bytes()
                tables[name] = text_rows(raw)
                hashes[name] = hashlib.sha256(raw).hexdigest()
    else:
        if not zipfile.is_zipfile(path):
            raise SystemExit(f"GTFS input is neither a directory nor ZIP: {path}")
        with zipfile.ZipFile(path) as zf:
            available = {n.rsplit("/", 1)[-1]: n for n in zf.namelist() if not n.endswith("/")}
            for name in names:
                member = available.get(name)
                if member:
                    raw = zf.read(member)
                    tables[name] = text_rows(raw)
                    hashes[name] = hashlib.sha256(raw).hexdigest()
    missing = [name for name in REQUIRED if name not in tables]
    if missing:
        raise SystemExit("GTFS normalization gate failed: missing " + ", ".join(missing))
    return tables, hashes


def as_float(value: str | None) -> float | None:
    if value in (None, ""):
        return None
    try:
        result = float(value)
    except ValueError:
        return None
    return result if math.isfinite(result) else None


def as_int(value: str | None) -> int | None:
    if value in (None, ""):
        return None
    try:
        return int(value)
    except ValueError:
        return None


def clean_colour(value: str | None) -> str | None:
    if not value:
        return None
    value = value.strip().lstrip("#").upper()
    if len(value) not in (6, 8) or any(c not in "0123456789ABCDEF" for c in value):
        return None
    return value


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--gtfs", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--license", default="STIB-MIVB Open Data Licence / verify upstream intake terms")
    parser.add_argument("--include-shapes", action="store_true")
    parser.add_argument("--min-stops", type=int, default=1)
    parser.add_argument("--min-routes", type=int, default=1)
    args = parser.parse_args()

    tables, table_hashes = load_tables(args.gtfs)

    stops: list[dict[str, Any]] = []
    for row in tables["stops.txt"]:
        stop_id = (row.get("stop_id") or "").strip()
        name = (row.get("stop_name") or "").strip()
        lat = as_float(row.get("stop_lat"))
        lon = as_float(row.get("stop_lon"))
        if not stop_id or not name or lat is None or lon is None:
            continue
        if not (-90 <= lat <= 90 and -180 <= lon <= 180):
            continue
        stops.append({
            "stop_id": stop_id,
            "stop_code": (row.get("stop_code") or "").strip() or None,
            "name": name,
            "wgs84": [round(lon, 7), round(lat, 7)],
            "location_type": as_int(row.get("location_type")),
            "parent_station": (row.get("parent_station") or "").strip() or None,
            "wheelchair_boarding": as_int(row.get("wheelchair_boarding")),
            "platform_code": (row.get("platform_code") or "").strip() or None,
        })
    stops.sort(key=lambda r: r["stop_id"])

    routes: list[dict[str, Any]] = []
    for row in tables["routes.txt"]:
        route_id = (row.get("route_id") or "").strip()
        if not route_id:
            continue
        routes.append({
            "route_id": route_id,
            "agency_id": (row.get("agency_id") or "").strip() or None,
            "short_name": (row.get("route_short_name") or "").strip() or None,
            "long_name": (row.get("route_long_name") or "").strip() or None,
            "route_type": as_int(row.get("route_type")),
            "colour": clean_colour(row.get("route_color")),
            "text_colour": clean_colour(row.get("route_text_color")),
        })
    routes.sort(key=lambda r: r["route_id"])

    trips: list[dict[str, Any]] = []
    for row in tables.get("trips.txt", []):
        trip_id = (row.get("trip_id") or "").strip()
        route_id = (row.get("route_id") or "").strip()
        if not trip_id or not route_id:
            continue
        trips.append({
            "trip_id": trip_id,
            "route_id": route_id,
            "service_id": (row.get("service_id") or "").strip() or None,
            "headsign": (row.get("trip_headsign") or "").strip() or None,
            "direction_id": as_int(row.get("direction_id")),
            "shape_id": (row.get("shape_id") or "").strip() or None,
            "wheelchair_accessible": as_int(row.get("wheelchair_accessible")),
        })
    trips.sort(key=lambda r: r["trip_id"])

    shapes: dict[str, list[list[float]]] | None = None
    if args.include_shapes and "shapes.txt" in tables:
        grouped: dict[str, list[tuple[int, float, float]]] = {}
        for row in tables["shapes.txt"]:
            sid = (row.get("shape_id") or "").strip()
            lat = as_float(row.get("shape_pt_lat"))
            lon = as_float(row.get("shape_pt_lon"))
            seq = as_int(row.get("shape_pt_sequence"))
            if not sid or lat is None or lon is None or seq is None:
                continue
            grouped.setdefault(sid, []).append((seq, lon, lat))
        shapes = {}
        for sid in sorted(grouped):
            points = sorted(grouped[sid], key=lambda p: p[0])
            shapes[sid] = [[round(lon, 7), round(lat, 7)] for _, lon, lat in points]

    if len(stops) < args.min_stops:
        raise SystemExit(f"STIB GTFS stop gate failed: {len(stops)} < {args.min_stops}")
    if len(routes) < args.min_routes:
        raise SystemExit(f"STIB GTFS route gate failed: {len(routes)} < {args.min_routes}")

    output: dict[str, Any] = {
        "format": FORMAT,
        "source": {
            "publisher": "STIB-MIVB",
            "license": args.license,
            "input": str(args.gtfs),
            "input_sha256": None if args.gtfs.is_dir() else sha256_file(args.gtfs),
            "table_sha256": table_hashes,
            "coordinate_reference": "GTFS WGS84 / EPSG:4326",
            "terms_must_be_preserved": True,
        },
        "stats": {
            "stop_count": len(stops),
            "route_count": len(routes),
            "trip_count": len(trips),
            "shape_count": 0 if shapes is None else len(shapes),
        },
        "stops": stops,
        "routes": routes,
        "trips": trips,
        "runtime_authorized": False,
        "production_authorized": False,
        "semantic_rules": [
            "Producer IDs are preserved.",
            "Route colours are producer data and must not be arbitrarily replaced.",
            "WGS84 coordinates are not silently treated as project metres.",
            "Existing STIB runtime/visual branches retain ownership."
        ],
    }
    if shapes is not None:
        output["shapes_wgs84"] = shapes

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"STIB_GTFS_NORMALIZATION_OK: {len(stops)} stops, {len(routes)} routes -> {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
