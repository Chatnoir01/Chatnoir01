#!/usr/bin/env python3
"""Compile one source-backed Brussels cell into a deterministic runtime candidate bundle.

The compiler consumes the five official UrbIS base-city layers produced by
``materialize_urbis_source_cell.py`` and emits the same compact contracts used by
Godot's streamed source-plan renderer. It is intentionally candidate-only:

- plan geometry is derived from official EPSG:31370 source;
- no building height is invented or promoted;
- no collision or terrain runtime authority is granted;
- no production runtime mount is authorized;
- street surfaces and network segments are clipped to the canonical 500 m cell
  so adjacent cells can stream independently without geometry ownership gaps.

The Lambert72 -> current game-world transform is the locked regional transform
already used by the C01 30k LoD2 world-geometry contract and the shipped source
cells. Changing it is a breaking world-coordinate migration, not a tuning knob.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from collections import Counter
from pathlib import Path
from typing import Any, Iterable

SOURCE_FORMAT = "grand-bruxelles-urbis-source-cell-v1"
BUILT_FORMAT = "grand-bruxelles-urbis-built-cell-v1"
RUNTIME_CELL_FORMAT = "grand-bruxelles-urbis-cell-runtime-v1"
RUNTIME_NETWORK_FORMAT = "grand-bruxelles-urbis-network-cell-runtime-v2"
CANDIDATE_FORMAT = "grand-bruxelles-runtime-candidate-bundle-v1"
CRS = "EPSG:31370"
CELL_SIZE_M = 500.0

LAMBERT_ORIGIN_E = 147868.29422791934
LAMBERT_ORIGIN_N = 169538.62414926197
WORLD_ANCHOR_X = -668.5
WORLD_ANCHOR_Z = 627.84
QUANTIZATION_DECIMALS = 3

REQUIRED_LAYERS: tuple[tuple[str, str], ...] = (
    ("buildings", "raw/buildings.geojson"),
    ("street_surfaces", "raw/street_surfaces.geojson"),
    ("street_axes", "raw/street_axes.geojson"),
    ("tram_network", "raw/tram_network.geojson"),
    ("train_network", "raw/train_network.geojson"),
)


def _json_digest(value: Any) -> str:
    payload = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def _file_sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _read_object(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def _write_json(path: Path, value: dict[str, Any], compact: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if compact:
        text = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    else:
        text = json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True)
    path.write_text(text + "\n", encoding="utf-8")


def _finite_pair(raw: Any) -> tuple[float, float] | None:
    if not isinstance(raw, list) or len(raw) < 2:
        return None
    try:
        x, y = float(raw[0]), float(raw[1])
    except (TypeError, ValueError):
        return None
    if not math.isfinite(x) or not math.isfinite(y):
        return None
    return x, y


def _world_point(easting: float, northing: float) -> list[float]:
    return [
        round(easting - LAMBERT_ORIGIN_E + WORLD_ANCHOR_X, QUANTIZATION_DECIMALS),
        round(-(northing - LAMBERT_ORIGIN_N) + WORLD_ANCHOR_Z, QUANTIZATION_DECIMALS),
    ]


def _feature_id(feature: dict[str, Any]) -> str:
    props = feature.get("properties") or {}
    value = props.get("INSPIRE_ID") or feature.get("id")
    if value not in (None, ""):
        return str(value)
    return "sha256:" + _json_digest(feature)


def _clean_ring(raw: Any) -> list[list[float]]:
    if not isinstance(raw, list):
        return []
    points: list[list[float]] = []
    for item in raw:
        pair = _finite_pair(item)
        if pair is None:
            return []
        point = [pair[0], pair[1]]
        if not points or point != points[-1]:
            points.append(point)
    if len(points) >= 2 and points[0] == points[-1]:
        points.pop()
    return points if len(points) >= 3 else []


def _outer_rings(geometry: dict[str, Any] | None) -> list[list[list[float]]]:
    if not isinstance(geometry, dict):
        return []
    kind = geometry.get("type")
    coords = geometry.get("coordinates")
    if kind == "Polygon" and isinstance(coords, list) and coords:
        ring = _clean_ring(coords[0])
        return [ring] if ring else []
    if kind == "MultiPolygon" and isinstance(coords, list):
        out: list[list[list[float]]] = []
        for polygon in coords:
            if not isinstance(polygon, list) or not polygon:
                return []
            ring = _clean_ring(polygon[0])
            if not ring:
                return []
            out.append(ring)
        return out
    return []


def _line_strings(geometry: dict[str, Any] | None) -> list[list[list[float]]]:
    if not isinstance(geometry, dict):
        return []
    kind = geometry.get("type")
    coords = geometry.get("coordinates")
    raw_lines: Iterable[Any]
    if kind == "LineString":
        raw_lines = [coords]
    elif kind == "MultiLineString":
        raw_lines = coords if isinstance(coords, list) else []
    else:
        return []
    out: list[list[list[float]]] = []
    for raw_line in raw_lines:
        if not isinstance(raw_line, list):
            return []
        line: list[list[float]] = []
        for item in raw_line:
            pair = _finite_pair(item)
            if pair is None:
                return []
            point = [pair[0], pair[1]]
            if not line or point != line[-1]:
                line.append(point)
        if len(line) >= 2:
            out.append(line)
    return out


def _inside(point: list[float], edge: str, bbox: tuple[float, float, float, float]) -> bool:
    x, y = point
    min_x, min_y, max_x, max_y = bbox
    if edge == "left":
        return x >= min_x
    if edge == "right":
        return x <= max_x
    if edge == "bottom":
        return y >= min_y
    return y <= max_y


def _edge_intersection(a: list[float], b: list[float], edge: str, bbox: tuple[float, float, float, float]) -> list[float]:
    ax, ay = a
    bx, by = b
    min_x, min_y, max_x, max_y = bbox
    if edge in {"left", "right"}:
        x = min_x if edge == "left" else max_x
        if math.isclose(ax, bx, abs_tol=1e-12):
            return [x, ay]
        t = (x - ax) / (bx - ax)
        return [x, ay + t * (by - ay)]
    y = min_y if edge == "bottom" else max_y
    if math.isclose(ay, by, abs_tol=1e-12):
        return [ax, y]
    t = (y - ay) / (by - ay)
    return [ax + t * (bx - ax), y]


def _clip_polygon(ring: list[list[float]], bbox: tuple[float, float, float, float]) -> list[list[float]]:
    output = [list(point) for point in ring]
    for edge in ("left", "right", "bottom", "top"):
        if not output:
            break
        input_points = output
        output = []
        previous = input_points[-1]
        for current in input_points:
            current_inside = _inside(current, edge, bbox)
            previous_inside = _inside(previous, edge, bbox)
            if current_inside:
                if not previous_inside:
                    output.append(_edge_intersection(previous, current, edge, bbox))
                output.append(current)
            elif previous_inside:
                output.append(_edge_intersection(previous, current, edge, bbox))
            previous = current
    cleaned: list[list[float]] = []
    for point in output:
        rounded = [round(float(point[0]), 9), round(float(point[1]), 9)]
        if not cleaned or rounded != cleaned[-1]:
            cleaned.append(rounded)
    if len(cleaned) >= 2 and cleaned[0] == cleaned[-1]:
        cleaned.pop()
    return cleaned if len(cleaned) >= 3 else []


def _clip_segment(a: list[float], b: list[float], bbox: tuple[float, float, float, float]) -> tuple[list[float], list[float]] | None:
    x0, y0 = a
    x1, y1 = b
    dx, dy = x1 - x0, y1 - y0
    min_x, min_y, max_x, max_y = bbox
    p = (-dx, dx, -dy, dy)
    q = (x0 - min_x, max_x - x0, y0 - min_y, max_y - y0)
    u0, u1 = 0.0, 1.0
    for pi, qi in zip(p, q):
        if math.isclose(pi, 0.0, abs_tol=1e-15):
            if qi < 0.0:
                return None
            continue
        t = qi / pi
        if pi < 0.0:
            if t > u1:
                return None
            u0 = max(u0, t)
        else:
            if t < u0:
                return None
            u1 = min(u1, t)
    if u0 > u1:
        return None
    ca = [x0 + u0 * dx, y0 + u0 * dy]
    cb = [x0 + u1 * dx, y0 + u1 * dy]
    if math.hypot(cb[0] - ca[0], cb[1] - ca[1]) <= 1e-8:
        return None
    return ca, cb


def _validate_source(cell_dir: Path) -> tuple[dict[str, Any], tuple[float, float, float, float], dict[str, dict[str, Any]]]:
    manifest = _read_object(cell_dir / "manifest.json")
    cell_id = cell_dir.name
    if manifest.get("format") != SOURCE_FORMAT:
        raise ValueError("unsupported source-cell manifest format")
    if manifest.get("cell_id") != cell_id:
        raise ValueError("source-cell identity mismatch")
    if manifest.get("crs") != CRS:
        raise ValueError("source-cell CRS mismatch")
    bbox_raw = manifest.get("bbox")
    if not isinstance(bbox_raw, list) or len(bbox_raw) != 4:
        raise ValueError("source-cell bbox missing")
    bbox = tuple(float(v) for v in bbox_raw)
    if not all(math.isfinite(v) for v in bbox):
        raise ValueError("source-cell bbox non-finite")
    if not math.isclose(bbox[2] - bbox[0], CELL_SIZE_M, abs_tol=1e-6) or not math.isclose(bbox[3] - bbox[1], CELL_SIZE_M, abs_tol=1e-6):
        raise ValueError("runtime candidate requires a canonical 500 m cell")
    layers = manifest.get("layers")
    if not isinstance(layers, dict):
        raise ValueError("source layers missing")
    documents: dict[str, dict[str, Any]] = {}
    for logical_name, expected_file in REQUIRED_LAYERS:
        spec = layers.get(logical_name)
        if not isinstance(spec, dict):
            raise ValueError(f"required source layer missing: {logical_name}")
        if spec.get("file") != expected_file:
            raise ValueError(f"source file contract drift for {logical_name}")
        path = cell_dir / expected_file
        if not path.is_file():
            raise ValueError(f"required source payload missing: {expected_file}")
        document = _read_object(path)
        if document.get("type") != "FeatureCollection" or not isinstance(document.get("features"), list):
            raise ValueError(f"invalid source FeatureCollection: {logical_name}")
        declared = spec.get("features")
        if not isinstance(declared, int) or isinstance(declared, bool) or declared != len(document["features"]):
            raise ValueError(f"source feature-count drift: {logical_name}")
        source_meta = document.get("grand_bruxelles_source")
        if not isinstance(source_meta, dict) or source_meta.get("cell_id") != cell_id or source_meta.get("crs") != CRS:
            raise ValueError(f"source provenance mismatch: {logical_name}")
        documents[logical_name] = document
    return manifest, bbox, documents


def _surface_level(props: dict[str, Any]) -> float:
    raw = props.get("LVL")
    if raw in (None, ""):
        raise ValueError("UrbIS street surface missing official LVL")
    value = float(raw)
    if not math.isfinite(value):
        raise ValueError("UrbIS street surface LVL non-finite")
    return round(value, 3)


def _buildings(document: dict[str, Any]) -> tuple[list[dict[str, Any]], int]:
    rows: list[dict[str, Any]] = []
    multipart = 0
    for feature in document.get("features") or []:
        props = feature.get("properties") or {}
        source_id = _feature_id(feature)
        rings = _outer_rings(feature.get("geometry"))
        if not rings:
            raise ValueError(f"unsupported/invalid building geometry: {source_id}")
        if len(rings) > 1:
            multipart += 1
        for part_index, ring in enumerate(rings):
            runtime_id = source_id if len(rings) == 1 else f"{source_id}#part{part_index}"
            row: dict[str, Any] = {
                "id": runtime_id,
                "source_id": source_id,
                "footprint": [_world_point(point[0], point[1]) for point in ring],
                "height_source": "absent_pending_validated_height_contract",
                "visual_height_available": False,
            }
            area = props.get("AREA")
            if area not in (None, ""):
                try:
                    area_value = float(area)
                    if math.isfinite(area_value):
                        row["source_area_m2"] = round(area_value, 2)
                except (TypeError, ValueError):
                    pass
            rows.append(row)
    rows.sort(key=lambda row: row["id"])
    return rows, multipart


def _street_surfaces(document: dict[str, Any], bbox: tuple[float, float, float, float]) -> tuple[list[dict[str, Any]], int]:
    rows: list[dict[str, Any]] = []
    clipped_parts = 0
    for feature in document.get("features") or []:
        props = feature.get("properties") or {}
        source_id = _feature_id(feature)
        level = _surface_level(props)
        rings = _outer_rings(feature.get("geometry"))
        if not rings:
            raise ValueError(f"unsupported/invalid street-surface geometry: {source_id}")
        for part_index, ring in enumerate(rings):
            clipped = _clip_polygon(ring, bbox)
            if not clipped:
                continue
            clipped_parts += 1
            rows.append({
                "id": source_id if len(rings) == 1 else f"{source_id}#part{part_index}",
                "source_id": source_id,
                "type": str(props.get("TYPE") or ""),
                "level": level,
                "street_fr": str(props.get("STRNAMEFRE") or ""),
                "street_nl": str(props.get("STRNAMEDUT") or ""),
                "polygon": [_world_point(point[0], point[1]) for point in clipped],
                "runtime_derivation": "official_plan_geometry_clipped_to_500m_cell",
            })
    rows.sort(key=lambda row: row["id"])
    return rows, clipped_parts


def _segment_key(kind: str, a: list[float], b: list[float]) -> tuple[Any, ...]:
    aa = (round(a[0], QUANTIZATION_DECIMALS), round(a[1], QUANTIZATION_DECIMALS))
    bb = (round(b[0], QUANTIZATION_DECIMALS), round(b[1], QUANTIZATION_DECIMALS))
    lo, hi = sorted((aa, bb))
    return (kind, lo, hi)


def _network_rows(document: dict[str, Any], bbox: tuple[float, float, float, float], *, default_kind: str, dedupe: set[tuple[Any, ...]]) -> tuple[list[dict[str, Any]], Counter[str]]:
    rows: list[dict[str, Any]] = []
    type_counts: Counter[str] = Counter()
    for feature in document.get("features") or []:
        props = feature.get("properties") or {}
        source_id = _feature_id(feature)
        source_type = str(props.get("TYPE") or "")
        if source_type:
            type_counts[source_type] += 1
        kind = default_kind
        if default_kind in {"rail", "tram", "train"}:
            upper = source_type.upper()
            if upper.startswith("TW"):
                kind = "tram"
            elif upper.startswith("RW"):
                kind = "train"
            elif default_kind == "rail":
                kind = "rail_unclassified"
        lines = _line_strings(feature.get("geometry"))
        if not lines:
            raise ValueError(f"unsupported/invalid network geometry: {source_id}")
        emitted_index = 0
        for line in lines:
            for index in range(len(line) - 1):
                clipped = _clip_segment(line[index], line[index + 1], bbox)
                if clipped is None:
                    continue
                world_a = _world_point(clipped[0][0], clipped[0][1])
                world_b = _world_point(clipped[1][0], clipped[1][1])
                key = _segment_key(kind, world_a, world_b)
                if key in dedupe:
                    continue
                dedupe.add(key)
                rows.append({
                    "id": f"{source_id}:{emitted_index}",
                    "source_id": source_id,
                    "kind": "street_axis" if kind == "street" else kind,
                    "type": source_type,
                    "street_fr": str(props.get("STRNAMEFRE") or ""),
                    "street_nl": str(props.get("STRNAMEDUT") or ""),
                    "points": [world_a, world_b],
                    "runtime_derivation": "official_source_segment_clipped_to_500m_cell",
                })
                emitted_index += 1
    rows.sort(key=lambda row: row["id"])
    return rows, type_counts


def build(cell_dir: Path, output_dir: Path) -> dict[str, Any]:
    source_manifest, bbox, documents = _validate_source(cell_dir)
    cell_id = cell_dir.name
    buildings, multipart_buildings = _buildings(documents["buildings"])
    surfaces, clipped_surface_parts = _street_surfaces(documents["street_surfaces"], bbox)

    street_dedupe: set[tuple[Any, ...]] = set()
    street_axes, street_types = _network_rows(documents["street_axes"], bbox, default_kind="street", dedupe=street_dedupe)
    rail_dedupe: set[tuple[Any, ...]] = set()
    tram_from_tram, tram_types = _network_rows(documents["tram_network"], bbox, default_kind="rail", dedupe=rail_dedupe)
    rail_from_train, train_types = _network_rows(documents["train_network"], bbox, default_kind="rail", dedupe=rail_dedupe)
    rail_rows = tram_from_tram + rail_from_train
    tram_rows = sorted((row for row in rail_rows if row["kind"] == "tram"), key=lambda row: row["id"])
    train_rows = sorted((row for row in rail_rows if row["kind"] == "train"), key=lambda row: row["id"])
    unclassified_rail = sorted((row for row in rail_rows if row["kind"] == "rail_unclassified"), key=lambda row: row["id"])

    coordinate_system = {
        "lambert_origin_e": LAMBERT_ORIGIN_E,
        "lambert_origin_n": LAMBERT_ORIGIN_N,
        "world_anchor_x": WORLD_ANCHOR_X,
        "world_anchor_z": WORLD_ANCHOR_Z,
        "axes": "X=east, Y=up, Z=south",
        "units": "metres",
        "coordinates_are_current_game_world": True,
        "quantization_decimals": QUANTIZATION_DECIMALS,
        "transform_contract": "region-lod2-C01-30000 locked world transform",
    }
    runtime_cell = {
        "format": RUNTIME_CELL_FORMAT,
        "cell_id": cell_id,
        "source": "Paradigm UrbIS WFS / EPSG:31370",
        "source_bbox": list(bbox),
        "coordinate_system": coordinate_system,
        "ownership": "buildings canonical owner; surfaces clipped to source_bbox",
        "accuracy": {
            "plan_geometry": "official_urbis",
            "street_surface_levels": "official_urbis",
            "building_heights": "absent_pending_validated_height_contract",
            "terrain_runtime": "not_authorized",
        },
        "authorization": {
            "candidate_only": True,
            "runtime_mount_authorized": False,
            "collision_authorized": False,
            "terrain_runtime_authorized": False,
            "jouable_promotion_authorized": False,
        },
        "stats": {
            "buildings": len(buildings),
            "street_surfaces": len(surfaces),
            "multipart_source_buildings": multipart_buildings,
            "clipped_surface_parts": clipped_surface_parts,
        },
        "buildings": buildings,
        "street_surfaces": surfaces,
    }
    runtime_network = {
        "format": RUNTIME_NETWORK_FORMAT,
        "cell_id": cell_id,
        "source_bbox": list(bbox),
        "coordinate_system": "current_game_world_xz_metres",
        "classification": {
            "street": "StreetAxes source layer",
            "tram": "UrbIS TYPE prefix TW across public rail layers",
            "train": "UrbIS TYPE prefix RW across public rail layers",
            "unclassified_rail": "preserved candidate evidence; not silently promoted",
        },
        "source_type_counts": {
            "street_axes": dict(sorted(street_types.items())),
            "tram_network": dict(sorted(tram_types.items())),
            "train_network": dict(sorted(train_types.items())),
        },
        "authorization": {
            "candidate_only": True,
            "mobility_runtime_authorized": False,
            "collision_authorized": False,
        },
        "stats": {
            "street_segments": len(street_axes),
            "tram_segments": len(tram_rows),
            "train_segments": len(train_rows),
            "unclassified_rail_segments": len(unclassified_rail),
        },
        "street_axes": street_axes,
        "tram_network": tram_rows,
        "train_network": train_rows,
        "unclassified_rail": unclassified_rail,
    }

    built_manifest = {
        "format": BUILT_FORMAT,
        "cell_id": cell_id,
        "crs": CRS,
        "bbox": list(bbox),
        "layers": source_manifest["layers"],
        "source_manifest_digest": _json_digest(source_manifest),
        "runtime": {
            "geometry_file": "runtime/cell.game.json",
            "geometry_format": RUNTIME_CELL_FORMAT,
            "geometry_stats": {"buildings": len(buildings), "street_surfaces": len(surfaces)},
            "network_file": "runtime/network.game.json",
            "network_format": RUNTIME_NETWORK_FORMAT,
            "network_stats": runtime_network["stats"],
        },
        "authorization": {
            "candidate_only": True,
            "runtime_mount_authorized": False,
            "collision_authorized": False,
            "terrain_runtime_authorized": False,
            "jouable_promotion_authorized": False,
        },
    }

    _write_json(output_dir / "manifest.json", built_manifest)
    _write_json(output_dir / "runtime" / "cell.game.json", runtime_cell, compact=True)
    _write_json(output_dir / "runtime" / "network.game.json", runtime_network, compact=True)

    input_files = {
        "manifest.json": _file_sha256(cell_dir / "manifest.json"),
        **{relative: _file_sha256(cell_dir / relative) for _, relative in REQUIRED_LAYERS},
    }
    output_files = {
        "manifest.json": _file_sha256(output_dir / "manifest.json"),
        "runtime/cell.game.json": _file_sha256(output_dir / "runtime" / "cell.game.json"),
        "runtime/network.game.json": _file_sha256(output_dir / "runtime" / "network.game.json"),
    }
    candidate = {
        "format": CANDIDATE_FORMAT,
        "cell_id": cell_id,
        "source_crs": CRS,
        "input_sha256": dict(sorted(input_files.items())),
        "output_sha256": dict(sorted(output_files.items())),
        "stats": {
            "buildings": len(buildings),
            "street_surfaces": len(surfaces),
            "street_segments": len(street_axes),
            "tram_segments": len(tram_rows),
            "train_segments": len(train_rows),
            "unclassified_rail_segments": len(unclassified_rail),
        },
        "safety": {
            "official_plan_geometry_only": True,
            "building_height_invented": False,
            "collision_generated": False,
            "runtime_mount_authorized": False,
            "jouable_promotion_authorized": False,
        },
        "next_gate": "validate_runtime_candidate_then_attach_maturity_evidence_before_promotion",
    }
    candidate["candidate_digest"] = _json_digest(candidate)
    _write_json(output_dir / "candidate.json", candidate)
    return candidate


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cell-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    try:
        result = build(args.cell_dir, args.output_dir)
    except Exception as exc:
        print(f"BUILD_RUNTIME_CANDIDATE_ERROR: {exc}")
        return 1
    stats = result["stats"]
    print(
        "BUILD_RUNTIME_CANDIDATE_OK "
        f"cell={result['cell_id']} buildings={stats['buildings']} surfaces={stats['street_surfaces']} "
        f"street_segments={stats['street_segments']} tram_segments={stats['tram_segments']} "
        f"train_segments={stats['train_segments']} runtime_mount_authorized=false "
        f"digest={result['candidate_digest']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
