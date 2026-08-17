#!/usr/bin/env python3
"""Derive a deterministic environment zone view from a committed OSM corridor slice.

This tool is intentionally network-free. It does not claim fresh/global OSM
completeness: it selects every supported environment point in the committed
slice within the source-declared environment radius of one named corridor
anchor, and records the exact upstream artifact digest.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from collections import Counter
from pathlib import Path
from typing import Any

SOURCE_LABEL = "OpenStreetMap contributors via Overpass API"
LICENSE = "ODbL-1.0"
SUPPORTED_KINDS = ("tree", "street_lamp", "bollard")
POLICY = "committed_corridor_anchor_radius_view_v1"


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


def project_relative(path: Path, project_root: Path) -> str:
    resolved = path.resolve()
    root = project_root.resolve()
    if resolved != root and root not in resolved.parents:
        raise ValueError(f"path escapes project root: {path}")
    return resolved.relative_to(root).as_posix()


def canonical_point(raw: dict[str, Any]) -> dict[str, Any]:
    if "osm_id" not in raw:
        raise ValueError(f"environment point missing osm_id: {raw!r}")
    kind = str(raw.get("kind", ""))
    if kind not in SUPPORTED_KINDS:
        raise ValueError(f"unsupported environment kind: {kind!r}")
    position = raw.get("position")
    if not isinstance(position, list) or len(position) != 2:
        raise ValueError(f"invalid environment position: {position!r}")
    return {
        "osm_id": int(raw["osm_id"]),
        "kind": kind,
        "position": [float(position[0]), float(position[1])],
    }


def corridor_anchor(source: dict[str, Any], anchor_id: str) -> tuple[list[float], float]:
    corridor = source.get("corridor")
    if not isinstance(corridor, dict):
        raise ValueError("upstream OSM slice has no corridor contract")
    anchors = corridor.get("anchors")
    if not isinstance(anchors, list):
        raise ValueError("upstream corridor anchors missing")
    matches = [
        row for row in anchors
        if isinstance(row, dict) and str(row.get("id", "")) == anchor_id
    ]
    if len(matches) != 1:
        raise ValueError(f"expected exactly one corridor anchor {anchor_id!r}, got {len(matches)}")
    anchor = matches[0]
    x = float(anchor["x"])
    z = float(anchor["z"])
    radii = corridor.get("selection_radius_m")
    if not isinstance(radii, dict):
        raise ValueError("upstream corridor selection radii missing")
    radius = float(radii.get("environment_points", -1.0))
    if not math.isfinite(radius) or radius <= 0.0:
        raise ValueError("invalid upstream environment selection radius")
    return [x, z], radius


def build(source_path: Path, output_path: Path, project_root: Path, anchor_id: str) -> dict[str, Any]:
    source = read_json(source_path)
    if source.get("format") != "grand-bruxelles-osm-v1":
        raise ValueError("unsupported upstream OSM slice format")
    if source.get("source") != SOURCE_LABEL or source.get("license") != LICENSE:
        raise ValueError("upstream OSM source/license mismatch")

    anchor, radius = corridor_anchor(source, anchor_id)
    raw_points = source.get("environment_points")
    if not isinstance(raw_points, list):
        raise ValueError("upstream environment_points missing")

    selected: list[dict[str, Any]] = []
    seen: set[int] = set()
    for raw in raw_points:
        if not isinstance(raw, dict):
            raise ValueError("invalid upstream environment point row")
        point = canonical_point(raw)
        osm_id = int(point["osm_id"])
        if osm_id in seen:
            raise ValueError(f"duplicate upstream OSM id: {osm_id}")
        seen.add(osm_id)
        x, z = map(float, point["position"])
        if math.hypot(x - anchor[0], z - anchor[1]) <= radius + 1e-9:
            selected.append(point)

    if not selected:
        raise ValueError(f"committed OSM slice contains no supported environment points near {anchor_id}")
    selected.sort(key=lambda row: (str(row["kind"]), int(row["osm_id"])))

    counts: Counter[str] = Counter(str(row["kind"]) for row in selected)
    stats = {kind: int(counts.get(kind, 0)) for kind in SUPPORTED_KINDS}
    stats["total"] = len(selected)

    result = {
        "format": "grand-bruxelles-osm-zone-environment-v1",
        "zone": anchor_id,
        "source": SOURCE_LABEL,
        "license": LICENSE,
        "coordinate_space": "game_xz_m",
        "upstream": {
            "path": project_relative(source_path, project_root),
            "sha256": sha256(source_path),
            "format": source.get("format"),
            "origin": source.get("origin"),
        },
        "selection": {
            "policy": POLICY,
            "anchor_id": anchor_id,
            "anchor": anchor,
            "radius_m": radius,
            "coverage_complete": False,
        },
        "stats": stats,
        "environment_points": selected,
    }
    write_json(output_path, result)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description="Extract a committed OSM corridor-anchor environment view")
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--anchor-id", required=True)
    args = parser.parse_args()
    result = build(args.source, args.output, args.project_root, args.anchor_id)
    print(
        "OSM_ANCHOR_VIEW_OK "
        f"zone={result['zone']} stats={result['stats']} "
        f"upstream_sha256={result['upstream']['sha256']} output={args.output}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
