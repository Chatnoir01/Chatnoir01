#!/usr/bin/env python3
"""Build clipped street/tram/train network segments for one UrbIS cell.

WFS bbox queries return whole lines that merely intersect the bbox. This module
clips every segment against the exact 500 m cell footprint before converting it
to the current game world.

Important UrbIS rail rule: the public WFS can expose overlapping/duplicated
content through ``TramNetwork`` and ``TrainNetwork``. UrbIS' own rail TYPE field
is authoritative for gameplay classification: ``TW`` = tramway and ``RW`` =
railway. Runtime output therefore filters by TYPE instead of trusting the WFS
layer name alone.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Iterable

TOOLS_DIR = Path(__file__).resolve().parent
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

from make_urbis_cell_runtime import game_point, parse_bbox

TRAM_TYPE_PREFIXES = ("TW",)
TRAIN_TYPE_PREFIXES = ("RW",)


def line_strings(geometry: dict[str, Any] | None) -> list[list[list[float]]]:
    if not geometry:
        return []
    kind = geometry.get("type")
    coords = geometry.get("coordinates", [])
    if kind == "LineString":
        return [coords]
    if kind == "MultiLineString":
        return [line for line in coords if line]
    return []


def clip_segment(
    a: list[float],
    b: list[float],
    bbox: tuple[float, float, float, float],
) -> tuple[list[float], list[float]] | None:
    """Liang-Barsky clipping against a cell rectangle."""
    x0, y0 = float(a[0]), float(a[1])
    x1, y1 = float(b[0]), float(b[1])
    min_x, min_y, max_x, max_y = bbox
    dx = x1 - x0
    dy = y1 - y0
    p = (-dx, dx, -dy, dy)
    q = (x0 - min_x, max_x - x0, y0 - min_y, max_y - y0)
    u1 = 0.0
    u2 = 1.0

    for pi, qi in zip(p, q):
        if abs(pi) < 1e-12:
            if qi < 0:
                return None
            continue
        ratio = qi / pi
        if pi < 0:
            if ratio > u2:
                return None
            u1 = max(u1, ratio)
        else:
            if ratio < u1:
                return None
            u2 = min(u2, ratio)

    if u1 > u2:
        return None
    start = [x0 + u1 * dx, y0 + u1 * dy]
    end = [x0 + u2 * dx, y0 + u2 * dy]
    if abs(start[0] - end[0]) < 1e-9 and abs(start[1] - end[1]) < 1e-9:
        return None
    return start, end


def feature_identifier(feature: dict[str, Any], props: dict[str, Any]) -> str:
    return str(props.get("INSPIRE_ID") or feature.get("id") or "")


def feature_type(props: dict[str, Any]) -> str:
    return str(props.get("TYPE") or props.get("TYP") or "").strip().upper()


def type_is_allowed(value: str, prefixes: Iterable[str] | None) -> bool:
    if prefixes is None:
        return True
    normalized = value.strip().upper()
    return any(normalized.startswith(prefix.upper()) for prefix in prefixes)


def build_layer_segments(
    document: dict[str, Any],
    bbox: tuple[float, float, float, float],
    layer_kind: str,
    *,
    allowed_type_prefixes: Iterable[str] | None = None,
) -> list[dict[str, Any]]:
    segments: list[dict[str, Any]] = []
    for feature in document.get("features", []):
        props = feature.get("properties", {}) or {}
        rail_type = feature_type(props)
        if not type_is_allowed(rail_type, allowed_type_prefixes):
            continue
        identifier = feature_identifier(feature, props)
        segment_index = 0
        for line in line_strings(feature.get("geometry")):
            for index in range(len(line) - 1):
                if len(line[index]) < 2 or len(line[index + 1]) < 2:
                    continue
                clipped = clip_segment(line[index], line[index + 1], bbox)
                if clipped is None:
                    continue
                start, end = clipped
                segments.append(
                    {
                        "id": f"{identifier}:{segment_index}",
                        "source_id": identifier,
                        "kind": layer_kind,
                        "type": rail_type,
                        "street_fr": str(props.get("STRNAMEFRE") or ""),
                        "street_nl": str(props.get("STRNAMEDUT") or ""),
                        "points": [game_point(start), game_point(end)],
                    }
                )
                segment_index += 1
    segments.sort(key=lambda item: item["id"])
    return segments


def source_type_counts(document: dict[str, Any]) -> dict[str, int]:
    counts: dict[str, int] = {}
    for feature in document.get("features", []):
        props = feature.get("properties", {}) or {}
        value = feature_type(props) or "<EMPTY>"
        counts[value] = counts.get(value, 0) + 1
    return dict(sorted(counts.items()))


def build_runtime(
    street_axes: dict[str, Any],
    tram_network: dict[str, Any],
    train_network: dict[str, Any],
    bbox: tuple[float, float, float, float],
    cell_id: str,
) -> dict[str, Any]:
    roads = build_layer_segments(street_axes, bbox, "street_axis")
    trams = build_layer_segments(
        tram_network,
        bbox,
        "tram",
        allowed_type_prefixes=TRAM_TYPE_PREFIXES,
    )
    trains = build_layer_segments(
        train_network,
        bbox,
        "train",
        allowed_type_prefixes=TRAIN_TYPE_PREFIXES,
    )
    return {
        "format": "grand-bruxelles-urbis-network-cell-runtime-v2",
        "cell_id": cell_id,
        "source_bbox": list(bbox),
        "coordinate_system": "current_game_world_xz_metres",
        "classification": {
            "street": "StreetAxes source layer",
            "tram": "UrbIS TYPE prefix TW",
            "train": "UrbIS TYPE prefix RW",
            "reason": "rail TYPE is authoritative because public WFS rail layers may overlap",
        },
        "source_type_counts": {
            "tram_network": source_type_counts(tram_network),
            "train_network": source_type_counts(train_network),
        },
        "stats": {
            "street_segments": len(roads),
            "tram_segments": len(trams),
            "train_segments": len(trains),
        },
        "street_axes": roads,
        "tram_network": trams,
        "train_network": trains,
    }


def load(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> int:
    parser = argparse.ArgumentParser(description="Build clipped UrbIS transport network runtime for one cell")
    parser.add_argument("--street-axes", type=Path, required=True)
    parser.add_argument("--tram-network", type=Path, required=True)
    parser.add_argument("--train-network", type=Path, required=True)
    parser.add_argument("--bbox", type=parse_bbox, required=True)
    parser.add_argument("--cell-id", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    runtime = build_runtime(
        load(args.street_axes),
        load(args.tram_network),
        load(args.train_network),
        args.bbox,
        args.cell_id,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(runtime, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"{args.cell_id}: network {runtime['stats']} -> {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
