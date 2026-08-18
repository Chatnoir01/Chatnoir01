#!/usr/bin/env python3
from __future__ import annotations

import json
import math
from pathlib import Path

from pyproj import Transformer

ROOT = Path(__file__).resolve().parents[1]
DTM = ROOT / "data/terrain/laeken_jette/atomium_dtm.game.json"
EVIDENCE = ROOT / "data/qa/photo_match/atomium_anchor_semantics_evidence.json"


def epsg_to_pixel(e: float, n: float, bbox: list[float], size: list[int]) -> tuple[float, float]:
    min_e, min_n, max_e, max_n = map(float, bbox)
    width, height = map(int, size)
    x = (e - min_e) / (max_e - min_e) * float(width - 1)
    y = (max_n - n) / (max_n - min_n) * float(height - 1)
    return x, y


def main() -> int:
    dtm = json.loads(DTM.read_text(encoding="utf-8"))
    evidence = json.loads(EVIDENCE.read_text(encoding="utf-8"))

    assert evidence["schema"] == "grand-bruxelles-atomium-anchor-semantics-v1"
    assert dtm["source_crs"] == "EPSG:31370"
    current = dtm["atomium_reference"]
    current_e = float(current["e"])
    current_n = float(current["n"])
    expected_current = list(map(float, evidence["current_reference_epsg31370"]))
    assert math.hypot(current_e - expected_current[0], current_n - expected_current[1]) < 0.001

    transformer = Transformer.from_crs("EPSG:4326", "EPSG:31370", always_xy=True)

    ticket = evidence["current_reference_wgs84_witness"]
    ticket_e, ticket_n = transformer.transform(float(ticket["lon"]), float(ticket["lat"]))
    ticket_error_m = math.hypot(ticket_e - current_e, ticket_n - current_n)
    assert ticket_error_m <= 0.02, f"production anchor no longer matches ticket-shop witness: {ticket_error_m:.4f} m"

    relation = evidence["monument_relation_position_witness"]
    relation_e, relation_n = transformer.transform(float(relation["lon"]), float(relation["lat"]))
    relation_distance_m = math.hypot(relation_e - current_e, relation_n - current_n)
    assert 20.0 <= relation_distance_m <= 40.0, f"unexpected monument relation separation: {relation_distance_m:.3f} m"

    ortho = evidence["official_orthophoto_crosscheck"]
    current_px = epsg_to_pixel(current_e, current_n, ortho["bbox_epsg31370"], ortho["raster_size_px"])
    relation_px = epsg_to_pixel(relation_e, relation_n, ortho["bbox_epsg31370"], ortho["raster_size_px"])
    recorded = list(map(float, ortho["recorded_current_reference_pixel"]))
    current_pixel_error = math.hypot(current_px[0] - recorded[0], current_px[1] - recorded[1])
    assert current_pixel_error <= 1.0, f"orthophoto crosscheck drifted: {current_pixel_error:.3f} px"

    width, height = map(int, ortho["raster_size_px"])
    assert 0.0 <= relation_px[0] < width and 0.0 <= relation_px[1] < height
    pixel_separation = math.hypot(relation_px[0] - current_px[0], relation_px[1] - current_px[1])
    nominal_resolution = sum(map(float, ortho["ground_resolution_m_per_px"])) / 2.0
    assert abs(pixel_separation * nominal_resolution - relation_distance_m) <= 0.15

    status = evidence["status"]
    assert status["current_reference_semantically_valid_as_architectural_center"] is False
    assert status["replacement_anchor_approved"] is False
    assert status["runtime_move_authorized"] is False
    assert status["support_pillar_geometry_authorized"] is False
    assert status["realism_complete"] is False

    print(
        "ATOMIUM_ANCHOR_SEMANTICS_AUDIT_OK "
        f"ticket_error_m={ticket_error_m:.6f} "
        f"relation_epsg31370=({relation_e:.3f},{relation_n:.3f}) "
        f"relation_distance_m={relation_distance_m:.3f} "
        f"current_px=({current_px[0]:.3f},{current_px[1]:.3f}) "
        f"relation_px=({relation_px[0]:.3f},{relation_px[1]:.3f}) "
        f"pixel_separation={pixel_separation:.3f} "
        "replacement_anchor_approved=false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
