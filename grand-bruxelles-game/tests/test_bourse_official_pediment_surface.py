from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HERO = ROOT / "data" / "urbis" / "heroes" / "bourse_lod2.game.json"
CANDIDATE = ROOT / "data" / "qa" / "bourse_portico_articulation_candidate.json"
RUNTIME = ROOT / "game" / "scripts" / "bourse_official_pediment_surface_runtime.gd"
PROJECT = ROOT / "project.godot"


def test_bourse_pediment_is_source_derived_and_mounted() -> None:
    hero = json.loads(HERO.read_text(encoding="utf-8"))
    candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))

    assert hero["schema"] == "grand-bruxelles-urbis-hero-mesh-v1"
    assert hero["hero_id"] == "bourse"
    assert hero["source"]["crs"] == "EPSG:31370"
    assert hero["source"]["license"] == "CC0-1.0"
    assert hero["source"]["package_sha256"] == candidate["source_contract"]["urbis3d_package_sha256"]
    assert "triangular pediment" in candidate["source_contract"]["heritage_front_fact"]

    runtime = RUNTIME.read_text(encoding="utf-8")
    project = PROJECT.read_text(encoding="utf-8")

    # The reveal must reuse committed LoD2 wall triangles and the authoritative
    # front envelope. It may not introduce authored pediment dimensions.
    assert 'HERO_GEOMETRY_PATH := "res://data/urbis/heroes/bourse_lod2.game.json"' in runtime
    assert 'CANDIDATE_PATH := "res://data/qa/bourse_portico_articulation_candidate.json"' in runtime
    assert '"WALLSURFACE"' in runtime
    assert "authoritative_front_envelope" in runtime
    assert "pediment_width_m" not in runtime
    assert "pediment_height_m" not in runtime
    assert "geometry_source_triangles" in runtime
    assert "source_package_sha256" in runtime
    assert "BourseOfficialPedimentSurfaceRuntime" in project
