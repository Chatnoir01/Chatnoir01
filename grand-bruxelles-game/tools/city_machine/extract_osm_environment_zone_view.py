#!/usr/bin/env python3
"""Extract a deterministic zone environment view from a committed OSM game slice.

This migration helper does not call the network and does not reconstruct WGS84
coordinates from rounded game-space points. It preserves an already-shipped
legacy subset while recording the exact upstream artifact digest.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from collections import Counter
from pathlib import Path
from typing import Any

SOURCE = "OpenStreetMap contributors via Overpass API"
LICENSE = "ODbL-1.0"
SUPPORTED_KINDS = ("tree", "street_lamp", "bollard")


def read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def relative_project_path(path: Path, project_root: Path) -> str:
    resolved = path.resolve()
    root = project_root.resolve()
    if resolved != root and root not in resolved.parents:
        raise ValueError(f"path escapes project root: {path}")
    return resolved.relative_to(root).as_posix()


def canonical_point(row: dict[str, Any]) -> dict[str, Any]:
    kind = str(row.get("kind", ""))
    if kind not in SUPPORTED_KINDS:
        raise ValueError(f"unsupported environment kind: {kind!r}")
    position = row.get("position")
    if not isinstance(position, list) or len(position) != 2:
        raise ValueError(f"invalid environment position: {position!r}")
    return {
        "osm_id": int(row["osm_id"]),
        "kind": kind,
        "position": [float(position[0]), float(position[1])],
    }


def build(
    source_path: Path,
    legacy_path: Path,
    output_path: Path,
    project_root: Path,
    zone: str,
    anchor_x: float,
    anchor_z: float,
    radius_m: float,
) -> dict[str, Any]:
    source = read_json(source_path)
    legacy = read_json(legacy_path)

    if source.get("format") != "grand-bruxelles-osm-v1":
        raise ValueError("unsupported upstream OSM slice format")
    if source.get("source") != SOURCE or source.get("license") != LICENSE:
        raise ValueError("upstream OSM source/license mismatch")
    if legacy.get("format") != "grand-bruxelles-osm-environment-points-v1":
        raise ValueError("unsupported legacy Anneessens environment format")
    if str(legacy.get("zone", "")) != zone:
        raise ValueError(f"legacy zone mismatch: expected {zone!r}")
    if float(legacy.get("radius_m", -1)) != float(radius_m):
        raise ValueError("legacy radius mismatch")

    source_points = source.get("environment_points")
    legacy_points = legacy.get("points")
    if not isinstance(source_points, list) or not isinstance(legacy_points, list):
        raise ValueError("environment point collections missing")

    source_by_id: dict[int, dict[str, Any]] = {}
    for raw in source_points:
        if not isinstance(raw, dict) or "osm_id" not in raw:
            continue
        point = canonical_point(raw)
        osm_id = int(point["osm_id"])
        if osm_id in source_by_id:
            raise ValueError(f"duplicate upstream OSM id: {osm_id}")
        source_by_id[osm_id] = point

    selected: list[dict[str, Any]] = []
    seen: set[int] = set()
    for raw in legacy_points:
        if not isinstance(raw, dict) or "osm_id" not in raw:
            raise ValueError("invalid legacy environment point")
        legacy_point = canonical_point(raw)
        osm_id = int(legacy_point["osm_id"])
        if osm_id in seen:
            raise ValueError(f"duplicate legacy OSM id: {osm_id}")
        seen.add(osm_id)
        upstream_point = source_by_id.get(osm_id)
        if upstream_point is None:
            raise ValueError(f"legacy OSM id missing from upstream slice: {osm_id}")
        if legacy_point != upstream_point:
            raise ValueError(f"legacy point drifted from upstream slice: {osm_id}")
        x, z = map(float, upstream_point["position"])
        if math.hypot(x - anchor_x, z - anchor_z) > radius_m + 1e-6:
            raise ValueError(f"legacy OSM id outside declared zone radius: {osm_id}")
        selected.append(upstream_point)

    if not selected:
        raise ValueError("legacy environment subset is empty")
    selected.sort(key=lambda row: (str(row["kind"]), int(row["osm_id"])))

    counts: Counter[str] = Counter(str(row["kind"]) for row in selected)
    stats = {kind: int(counts.get(kind, 0)) for kind in SUPPORTED_KINDS}
    stats["total"] = len(selected)

    return {
        "format": "grand-bruxelles-osm-zone-environment-v1",
        "zone": zone,
        "source": SOURCE,
        "license": LICENSE,
        "coordinate_space": "game_xz_m",
        "upstream": {
            "path": relative_project_path(source_path, project_root),
            "sha256": sha256(source_path),
            "format": source.get("format"),
            "origin": source.get("origin"),
        },
        "selection": {
            "policy": "preserve_existing_runtime_subset_v1",
            "anchor": [float(anchor_x), float(anchor_z)],
            "radius_m": float(radius_m),
            "coverage_complete": False,
            "osm_ids": [int(row["osm_id"]) for row in selected],
        },
        "stats": stats,
        "environment_points": selected,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Extract a deterministic OSM zone environment view")
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--legacy", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--zone", required=True)
    parser.add_argument("--anchor-x", type=float, required=True)
    parser.add_argument("--anchor-z", type=float, required=True)
    parser.add_argument("--radius-m", type=float, required=True)
    args = parser.parse_args()

    result = build(
        args.source,
        args.legacy,
        args.output,
        args.project_root,
        args.zone,
        args.anchor_x,
        args.anchor_z,
        args.radius_m,
    )
    write_json(args.output, result)
    print(
        "OSM_ZONE_VIEW_OK "
        f"zone={args.zone} total={result['stats']['total']} "
        f"upstream_sha256={result['upstream']['sha256']} output={args.output}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
