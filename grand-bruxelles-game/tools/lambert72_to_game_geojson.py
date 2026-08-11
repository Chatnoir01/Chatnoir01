#!/usr/bin/env python3
"""Convert an EPSG:31370 GeoJSON layer to Grand Bruxelles local game metres.

The converter intentionally does not reproject CRS. Input must already be Belgian
Lambert 72 (EPSG:31370), ideally exported/cropped by QGIS or an official service.
It recursively transforms all GeoJSON coordinates using the project's local origin.

Godot mapping:
    x = E - origin_e
    z = -(N - origin_n)
    y = altitude - origin_altitude  (only when an input Z exists)

2D coordinates become [x, z]. 3D coordinates become [x, y, z] so the output is
ready for game-oriented import code rather than a standards-compliant geographic CRS.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

DEFAULT_ORIGIN_E = 147868.29422791934
DEFAULT_ORIGIN_N = 169538.62414926197
DEFAULT_ORIGIN_ALTITUDE = 0.0


def transform_position(
    position: list[float], origin_e: float, origin_n: float, origin_altitude: float
) -> list[float]:
    if len(position) < 2:
        raise ValueError(f"Invalid position: {position!r}")
    east = float(position[0])
    north = float(position[1])
    game_x = east - origin_e
    game_z = -(north - origin_n)
    if len(position) >= 3:
        altitude = float(position[2])
        game_y = altitude - origin_altitude
        return [game_x, game_y, game_z]
    return [game_x, game_z]


def transform_coordinates(
    coordinates: Any, origin_e: float, origin_n: float, origin_altitude: float
) -> Any:
    if not isinstance(coordinates, list):
        raise ValueError("GeoJSON coordinates must be arrays")
    if coordinates and isinstance(coordinates[0], (int, float)):
        return transform_position(coordinates, origin_e, origin_n, origin_altitude)
    return [
        transform_coordinates(child, origin_e, origin_n, origin_altitude)
        for child in coordinates
    ]


def transform_geometry(
    geometry: dict[str, Any] | None,
    origin_e: float,
    origin_n: float,
    origin_altitude: float,
) -> dict[str, Any] | None:
    if geometry is None:
        return None
    geometry = dict(geometry)
    geometry_type = geometry.get("type")
    if geometry_type == "GeometryCollection":
        geometry["geometries"] = [
            transform_geometry(g, origin_e, origin_n, origin_altitude)
            for g in geometry.get("geometries", [])
        ]
        return geometry
    if "coordinates" in geometry:
        geometry["coordinates"] = transform_coordinates(
            geometry["coordinates"], origin_e, origin_n, origin_altitude
        )
    return geometry


def convert_document(
    document: dict[str, Any],
    origin_e: float,
    origin_n: float,
    origin_altitude: float,
) -> dict[str, Any]:
    output = dict(document)
    doc_type = output.get("type")

    if doc_type == "FeatureCollection":
        converted = []
        for feature in output.get("features", []):
            feature_out = dict(feature)
            feature_out["geometry"] = transform_geometry(
                feature_out.get("geometry"), origin_e, origin_n, origin_altitude
            )
            converted.append(feature_out)
        output["features"] = converted
    elif doc_type == "Feature":
        output["geometry"] = transform_geometry(
            output.get("geometry"), origin_e, origin_n, origin_altitude
        )
    else:
        output = transform_geometry(output, origin_e, origin_n, origin_altitude) or {}

    output["grand_bruxelles_coordinate_system"] = {
        "source_crs": "EPSG:31370",
        "origin_e": origin_e,
        "origin_n": origin_n,
        "origin_altitude": origin_altitude,
        "axes": "X=east, Y=up, Z=south",
        "units": "metres",
    }
    return output


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path, help="EPSG:31370 GeoJSON input")
    parser.add_argument("output", type=Path, help="Game-local JSON output")
    parser.add_argument("--origin-e", type=float, default=DEFAULT_ORIGIN_E)
    parser.add_argument("--origin-n", type=float, default=DEFAULT_ORIGIN_N)
    parser.add_argument("--origin-altitude", type=float, default=DEFAULT_ORIGIN_ALTITUDE)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    with args.input.open("r", encoding="utf-8") as handle:
        document = json.load(handle)
    converted = convert_document(
        document, args.origin_e, args.origin_n, args.origin_altitude
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8") as handle:
        json.dump(converted, handle, ensure_ascii=False, separators=(",", ":"))
        handle.write("\n")
    feature_count = len(converted.get("features", [])) if isinstance(converted, dict) else 0
    print(f"Converted {feature_count} features -> {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
