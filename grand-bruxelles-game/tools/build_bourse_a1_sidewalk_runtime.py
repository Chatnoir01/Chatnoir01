#!/usr/bin/env python3
"""Build the A1 source-complete bounded Bourse sidewalk runtime candidate.

The build is deliberately constrained to the exact envelope already used by the
shipped Bourse sidewalk evidence: current seven official StreetSurfaces + 8 m.
No live feature outside that envelope can enter the candidate.
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

import extract_bourse_official_sidewalks as sidewalk_source  # noqa: E402
from audit_bourse_a1_sidewalk_coverage import _fully_contained  # noqa: E402

CURRENT_RUNTIME = ROOT / "data" / "urbis" / "bourse_official_sidewalks.game.json"
BASE_SURFACES = ROOT / "data" / "urbis" / "bourse_street_surfaces.game.json"
LEGACY_BBOX_TOLERANCE_M = 0.005


def _load(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _ring_bbox(ring: list[list[float]]) -> tuple[float, float, float, float]:
    return (
        min(float(p[0]) for p in ring),
        min(float(p[1]) for p in ring),
        max(float(p[0]) for p in ring),
        max(float(p[1]) for p in ring),
    )


def _rings_bbox(rings: list[list[list[float]]]) -> tuple[float, float, float, float]:
    boxes = [_ring_bbox(ring) for ring in rings if ring]
    if not boxes:
        raise ValueError("feature has no usable source ring")
    return (
        min(box[0] for box in boxes),
        min(box[1] for box in boxes),
        max(box[2] for box in boxes),
        max(box[3] for box in boxes),
    )


def _bbox_delta_m(a: tuple[float, float, float, float], b: tuple[float, float, float, float]) -> float:
    return max(abs(a[i] - b[i]) for i in range(4))


def _world_transform() -> tuple[float, float, float, float]:
    base = _load(BASE_SURFACES)
    evidence = base.get("world_coordinate_evidence", {})
    lambert = evidence.get("lambert72_origin", [])
    world = evidence.get("world_origin_xz", [])
    if not isinstance(lambert, list) or len(lambert) != 2 or not isinstance(world, list) or len(world) != 2:
        raise ValueError("Bourse world transform evidence is incomplete")
    return float(lambert[0]), float(lambert[1]), float(world[0]), float(world[1])


def _to_world(point: list[float], transform: tuple[float, float, float, float]) -> list[float]:
    if len(point) < 2:
        raise ValueError("source point is not 2D")
    lx, ly, wx, wz = transform
    sx, sy = float(point[0]), float(point[1])
    return [sx - lx + wx, wz - (sy - ly)]


def _world_rings(rings: list[list[list[float]]], transform: tuple[float, float, float, float]) -> list[list[list[float]]]:
    return [[_to_world(point, transform) for point in ring] for ring in rings]


def _validate_legacy_geometry(
    live_by_id: dict[str, dict[str, Any]], current: dict[str, Any]
) -> None:
    current_rows = {
        str(row.get("source_id", "")): row
        for row in current.get("sidewalks", [])
        if isinstance(row, dict)
    }
    for source_id, row in current_rows.items():
        live = live_by_id.get(source_id)
        if live is None:
            raise AssertionError(f"legacy official sidewalk vanished from live bounded source: {source_id}")
        old_rings = row.get("source_rings_epsg31370", [])
        new_rings = live.get("source_rings_epsg31370", [])
        if not old_rings or not new_rings:
            raise AssertionError(f"legacy sidewalk lacks comparable source geometry: {source_id}")
        delta = _bbox_delta_m(_rings_bbox(old_rings), _rings_bbox(new_rings))
        if delta > LEGACY_BBOX_TOLERANCE_M:
            raise AssertionError(
                f"legacy sidewalk source drift exceeds {LEGACY_BBOX_TOLERANCE_M} m for {source_id}: {delta:.6f} m"
            )


def build() -> dict[str, Any]:
    current = _load(CURRENT_RUNTIME)
    if current.get("curb_elevation_resolved") is not False:
        raise AssertionError("A1 cannot build from a runtime that claims curb elevation")

    bbox = sidewalk_source._surface_bbox(ROOT)
    payload, response_sha256 = sidewalk_source.fetch_live(bbox)
    intersecting = sidewalk_source.extract_features(payload, bbox)
    contained = [feature for feature in intersecting if _fully_contained(feature, bbox)]
    contained.sort(key=lambda feature: str(feature.get("source_id", "")))
    if not contained:
        raise AssertionError("no fully-contained official sidewalks in the locked Bourse envelope")

    live_by_id = {str(feature.get("source_id", "")): feature for feature in contained}
    if "" in live_by_id:
        raise AssertionError("live sidewalk feature has empty source ID")
    if len(live_by_id) != len(contained):
        raise AssertionError("duplicate live sidewalk source IDs in locked Bourse envelope")

    legacy_ids = sorted(str(v) for v in current.get("selection", {}).get("source_ids", []))
    if not legacy_ids:
        raise AssertionError("current Bourse runtime has no legacy source IDs")
    missing_legacy = sorted(set(legacy_ids) - set(live_by_id))
    if missing_legacy:
        raise AssertionError(f"legacy source IDs are no longer fully contained: {missing_legacy}")
    _validate_legacy_geometry(live_by_id, current)

    transform = _world_transform()
    rows: list[dict[str, Any]] = []
    for feature in contained:
        source_id = str(feature["source_id"])
        source_rings = feature.get("source_rings_epsg31370", [])
        if not isinstance(source_rings, list) or not source_rings:
            raise AssertionError(f"missing source rings for {source_id}")
        ssft = feature.get("ssft")
        rows.append(
            {
                "source_id": source_id,
                "source_level": 0,
                "source_rings_epsg31370": source_rings,
                "ssft_uninterpreted": ssft,
                "world_rings_xz": _world_rings(source_rings, transform),
            }
        )

    live_ids = [row["source_id"] for row in rows]
    return {
        "schema": "grand-bruxelles-bourse-official-sidewalk-runtime-v1",
        "source": {
            "publisher": "Brussels Mobility / Paradigm",
            "source_page": sidewalk_source.SOURCE_PAGE,
            "wfs": sidewalk_source.WFS_URL,
            "layer": sidewalk_source.LAYER,
            "crs": sidewalk_source.CRS,
            "license": sidewalk_source.LICENSE,
            "response_sha256": response_sha256,
            "pre_a1_evidence_artifact_digest": current.get("source", {}).get("evidence_artifact_digest"),
        },
        "selection": {
            "basis": "all fully-contained official sidewalk features inside the existing seven-StreetSurface + 8 m Bourse envelope",
            "bbox_epsg31370": list(bbox),
            "feature_count": len(rows),
            "source_ids": live_ids,
            "a1_legacy_source_ids": legacy_ids,
            "a1_added_source_ids": sorted(set(live_ids) - set(legacy_ids)),
            "geography_expanded": False,
        },
        "sidewalks": rows,
        "runtime_approved": False,
        "realism_complete": False,
        "curb_elevation_resolved": False,
        "presentation_height_is_renderer_bias_only": True,
        "notes": (
            "A1 completes horizontal official sidewalk coverage only inside the previously bounded Bourse envelope. "
            "No physical curb height, paving dimension, collision elevation, or new geography is asserted."
        ),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    candidate = build()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(candidate, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    selection = candidate["selection"]
    print(
        "BOURSE_A1_SIDEWALK_CANDIDATE_OK",
        f"features={selection['feature_count']}",
        f"legacy={len(selection['a1_legacy_source_ids'])}",
        f"added={len(selection['a1_added_source_ids'])}",
        f"geography_expanded={selection['geography_expanded']}",
        f"source_sha256={candidate['source']['response_sha256']}",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
