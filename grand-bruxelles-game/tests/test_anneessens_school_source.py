from __future__ import annotations

import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "data" / "osm" / "anneessens_school_256375327.game.json"
ANNEESSENS = (-272.04, -217.07)
OSM_ID = 256375327


def test_school_landmark_is_committed_from_exact_osm_way() -> None:
    assert SOURCE.exists(), "Anneessens landmark source snapshot is missing"
    data = json.loads(SOURCE.read_text(encoding="utf-8"))
    assert data["source"] == "OpenStreetMap contributors"
    assert data["license"] == "ODbL-1.0"
    assert data["osm_type"] == "way"
    assert data["osm_id"] == OSM_ID
    assert data["source_url"].endswith(f"/way/{OSM_ID}/full.json")
    footprint = data["footprint"]
    assert len(footprint) >= 4
    assert footprint[0] != footprint[-1], "runtime footprint must not duplicate closing point"
    cx = sum(float(point[0]) for point in footprint) / len(footprint)
    cz = sum(float(point[1]) for point in footprint) / len(footprint)
    assert math.hypot(cx - ANNEESSENS[0], cz - ANNEESSENS[1]) < 100.0


def test_heritage_contract_only_claims_documented_frontage_traits() -> None:
    data = json.loads(SOURCE.read_text(encoding="utf-8"))
    heritage = data["heritage_contract"]
    assert heritage["source"] == "monument.heritage.brussels"
    assert heritage["main_facade_bays"] == 5
    assert heritage["projecting_gabled_bays"] == [2, 4]
    assert heritage["central_loggia"] is True
    assert heritage["brick_with_white_and_blue_stone"] is True
    assert heritage["slate_roof"] is True
    assert "height_m" not in heritage
