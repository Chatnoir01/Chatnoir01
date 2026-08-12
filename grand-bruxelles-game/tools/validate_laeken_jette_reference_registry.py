#!/usr/bin/env python3
"""Validate Laeken/Jette realism-reference provenance and measured-state claims."""

from __future__ import annotations

import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REF = ROOT / "data" / "reference" / "laeken_jette"
SRC = ROOT / "data" / "sources" / "laeken_jette"


def load(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def close(a: float, b: float, tol: float = 0.02) -> bool:
    return math.isfinite(a) and abs(a - b) <= tol


def main() -> int:
    realism = load(REF / "realism_pass1.json")
    jette = load(REF / "jette_photo_references.json")
    photo_match = load(REF / "photo_match_views.json")
    heights = load(SRC / "building_height_integration_validation.json")

    assert realism["schema"] >= 2
    measured = realism["measured_height_validation"]
    assert measured["status"] == "passed"
    assert measured["source_feature_count"] == heights["source_feature_count"]
    assert measured["derived_height_count"] == heights["source_derived_height_count"]
    assert measured["fallback_count"] == heights["source_quality_counts"]["insufficient"]
    coverage = 100.0 * measured["derived_height_count"] / measured["source_feature_count"]
    assert close(measured["derived_coverage_percent"], coverage)
    assert "DSM-DTM" in realism["current_visual_rules"]["building_heights"]
    assert "temporary pending" not in realism["current_visual_rules"]["building_heights"].lower()

    refs = {item["id"]: item for item in jette["references"]}
    miroir = refs["miroir_commons_2011"]
    assert miroir["license"] == "CC BY-SA 3.0"
    assert miroir["source_location_semantics"] == "depicted_place_not_camera_position"
    assert miroir["embedded_asset"] is False
    assert len(miroir["source_wgs84_depicted_place"]) == 2
    assert len(miroir["source_epsg31370_depicted_place"]) == 2
    assert len(miroir["source_game_xz_depicted_place"]) == 2
    note = miroir["source_coordinate_note"].lower()
    assert "not photographer" in note
    assert "not a surveyed camera position" in note

    origin = jette["project_origin"]
    e, n = miroir["source_epsg31370_depicted_place"]
    x, z = miroir["source_game_xz_depicted_place"]
    assert close(x, e - origin["epsg31370_e"])
    assert close(z, -(n - origin["epsg31370_n"]))

    gate = photo_match.get("quality_gate", {})
    minimum_views = int(gate.get("minimum_reference_views", 0))
    views = photo_match["views"]
    assert minimum_views >= 3, "photo-match gate must require at least three reference views"
    assert len(views) >= minimum_views, (
        f"photo-match registry has {len(views)} views but gate requires {minimum_views}"
    )
    ids = [view.get("id") for view in views]
    assert len(ids) == len(set(ids)), "photo-match benchmark IDs must be unique"
    urls = []
    for view in views:
        status = view.get("status", "")
        reference = view.get("reference", {})
        assert reference.get("url"), f"{view.get('id')}: missing reference URL"
        assert reference.get("license"), f"{view.get('id')}: missing reference license"
        assert reference.get("usage"), f"{view.get('id')}: missing reference usage policy"
        assert len(view.get("comparison_checks", [])) >= 5, (
            f"{view.get('id')}: photo-match benchmark needs at least five visual checks"
        )
        assert view.get("resolution") == [1280, 720], (
            f"{view.get('id')}: benchmark capture resolution must stay deterministic"
        )
        assert 35.0 <= float(view.get("fov_degrees", 0.0)) <= 75.0, (
            f"{view.get('id')}: implausible benchmark FOV"
        )
        if "provisional" in status or "pending" in status:
            uncertainty = " ".join(
                [
                    str(view.get("camera_claim", "")),
                    str(reference.get("usage", "")),
                ]
            ).lower()
            assert "provisional" in uncertainty or "survey" in uncertainty or "no photographer" in uncertainty, (
                f"{view.get('id')}: uncertain benchmark must explicitly state camera uncertainty"
            )
        urls.append(reference["url"])
    assert len(set(urls)) >= 3, "three-view gate must use three independently registered reference pages"

    policy = jette["reference_policy"]
    assert "never infer" in policy["camera_claim_rule"].lower()
    assert policy["geometry_authority"][0] == "UrbIS WFS"

    print(
        "LAEKEN_JETTE_REFERENCE_REGISTRY_OK: "
        f"height_coverage={coverage:.2f}% refs={len(refs)} benchmarks={len(views)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
