#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data" / "urbis" / "bourse_geotagged_context" / "1645621.game.json"
SCRIPT = ROOT / "game" / "scripts" / "urbis_bourse_geotagged_frontage.gd"
EXPECTED_PACKAGE = "cf8449d1a62b0e47aafe6d715ff6a2739f5c48f6d75995f7f418305a5d6cf3d2"
EXPECTED_ID = "https://databrussels.be/id/building/1645621"


def test_official_frontage_1645621_contract():
    data = json.loads(DATA.read_text(encoding="utf-8"))
    assert data["schema"] == "grand-bruxelles-urbis-context-mesh-v1"
    assert data["source"]["provider"] == "Paradigm / Brussels-Capital Region"
    assert data["source"]["dataset"] == "UrbIS - 3D Constructions"
    assert data["source"]["crs"] == "EPSG:31370"
    assert data["source"]["license"] == "CC0-1.0"
    assert data["source"]["package_sha256"] == EXPECTED_PACKAGE
    assert data["source"]["building_2d_id"] == EXPECTED_ID
    assert data["source"]["solid_count"] == 2
    assert data["evidence"]["height_m"] == 24.789
    assert data["evidence"]["face_count"] == 37
    assert data["evidence"]["triangle_count"] == 96
    assert data["evidence"]["face_type_counts"] == {
        "ROOFSURFACE": 12,
        "GROUNDSURFACE": 2,
        "WALLSURFACE": 23,
    }
    assert data["runtime_approved"] is False


def test_frontage_runtime_mounts_exact_source_without_authored_massing():
    text = SCRIPT.read_text(encoding="utf-8")
    assert "1645621.game.json" in text
    assert EXPECTED_ID in text
    assert '"WALLSURFACE"' in text
    assert '"ROOFSURFACE"' in text
    assert '"GROUNDSURFACE"' not in text.split("func _build_geometry", 1)[1]
    assert 'set_meta("runtime_approved", false)' in text
    assert 'set_meta("realism_complete", false)' in text
