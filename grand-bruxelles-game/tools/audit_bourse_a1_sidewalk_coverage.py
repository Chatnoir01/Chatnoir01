#!/usr/bin/env python3
"""A1 RED-first audit: prove the bounded Bourse sidewalk runtime slice is complete.

The official live evidence query is *not* allowed to expand geography: it reuses the
same seven StreetSurface + 8 m envelope already established by the shipped Bourse
sidewalk evidence workflow. A1 fails closed while the committed runtime promotes
only a subset of official sidewalk features fully contained in that envelope.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

import extract_bourse_official_sidewalks as sidewalk_source  # noqa: E402

RUNTIME = ROOT / "data" / "urbis" / "bourse_official_sidewalks.game.json"
EPS = 1e-6


def _ring_bbox(ring: list[list[float]]) -> tuple[float, float, float, float]:
    return (
        min(float(p[0]) for p in ring),
        min(float(p[1]) for p in ring),
        max(float(p[0]) for p in ring),
        max(float(p[1]) for p in ring),
    )


def _bbox_inside(inner: tuple[float, float, float, float], outer: tuple[float, float, float, float]) -> bool:
    return (
        inner[0] >= outer[0] - EPS
        and inner[1] >= outer[1] - EPS
        and inner[2] <= outer[2] + EPS
        and inner[3] <= outer[3] + EPS
    )


def _fully_contained(feature: dict[str, Any], bbox: tuple[float, float, float, float]) -> bool:
    rings = feature.get("source_rings_epsg31370", [])
    if not isinstance(rings, list) or not rings:
        return False
    return all(_bbox_inside(_ring_bbox(ring), bbox) for ring in rings if isinstance(ring, list) and ring)


def main() -> int:
    runtime = json.loads(RUNTIME.read_text(encoding="utf-8"))
    if runtime.get("runtime_approved") is not False or runtime.get("realism_complete") is not False:
        raise AssertionError("Bourse sidewalk slice must remain runtime-unapproved / realism-incomplete")
    if runtime.get("curb_elevation_resolved") is not False:
        raise AssertionError("A1 must not claim a curb elevation")

    bbox = sidewalk_source._surface_bbox(ROOT)
    payload, response_sha256 = sidewalk_source.fetch_live(bbox)
    intersecting = sidewalk_source.extract_features(payload, bbox)
    contained = [feature for feature in intersecting if _fully_contained(feature, bbox)]

    live_ids = sorted(str(feature.get("source_id", "")) for feature in contained)
    runtime_ids = sorted(str(v) for v in runtime.get("selection", {}).get("source_ids", []))
    runtime_rows = sorted(str(row.get("source_id", "")) for row in runtime.get("sidewalks", []) if isinstance(row, dict))

    if runtime_ids != runtime_rows:
        raise AssertionError("runtime selection IDs and committed sidewalk rows disagree")
    missing = sorted(set(live_ids) - set(runtime_ids))
    extra = sorted(set(runtime_ids) - set(live_ids))

    print(
        "BOURSE_A1_SIDEWALK_COVERAGE_MEASURE",
        f"live_intersecting={len(intersecting)}",
        f"live_fully_contained={len(contained)}",
        f"runtime={len(runtime_ids)}",
        f"missing={len(missing)}",
        f"extra={len(extra)}",
        f"source_sha256={response_sha256}",
    )
    print("BOURSE_A1_MISSING_IDS", json.dumps(missing, ensure_ascii=False))
    if extra:
        print("BOURSE_A1_EXTRA_IDS", json.dumps(extra, ensure_ascii=False))

    if runtime_ids != live_ids:
        raise AssertionError(
            "A1 causal RED: bounded official sidewalk coverage is incomplete: "
            f"runtime={len(runtime_ids)} fully_contained={len(live_ids)} missing={len(missing)} extra={len(extra)}"
        )

    print("BOURSE_A1_SIDEWALK_COVERAGE_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
