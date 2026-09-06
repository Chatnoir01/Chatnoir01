#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "project.godot"
SCRIPT_A = ROOT / "game/scripts/grand_place_official_lod2_1655673.gd"
SCRIPT_B = ROOT / "game/scripts/grand_place_official_lod2_1786758.gd"
DATA_A = ROOT / "data/urbis/grand_place_lod2/1655673.game.json"
DATA_B = ROOT / "data/urbis/grand_place_lod2/1786758.game.json"
PACKAGE_SHA256 = "cf8449d1a62b0e47aafe6d715ff6a2739f5c48f6d75995f7f418305a5d6cf3d2"
EXPECTED = {
    "1655673": {
        "autoload": 'GrandPlaceOfficialLod2="*res://game/scripts/grand_place_official_lod2_1655673.gd"',
        "script": SCRIPT_A,
        "data": DATA_A,
        "triangles": 262,
    },
    "1786758": {
        "autoload": 'GrandPlaceOfficialLod2Next="*res://game/scripts/grand_place_official_lod2_1786758.gd"',
        "script": SCRIPT_B,
        "data": DATA_B,
        "triangles": 196,
    },
}


def validate(project_text: str | None = None) -> None:
    project = PROJECT.read_text(encoding="utf-8") if project_text is None else project_text
    assert 'run/main_scene="res://game/main.tscn"' in project
    for building_id, contract in EXPECTED.items():
        assert project.count(contract["autoload"]) == 1, f"official LoD2 {building_id} is not mounted exactly once"
        script_text = contract["script"].read_text(encoding="utf-8")
        expected_data_path = f'res://data/urbis/grand_place_lod2/{building_id}.game.json'
        assert f'const GEOMETRY_PATH := "{expected_data_path}"' in script_text
        assert f'https://databrussels.be/id/building/{building_id}' in script_text
        assert PACKAGE_SHA256 in script_text
        assert 'runtime_approved' in script_text

        data = json.loads(contract["data"].read_text(encoding="utf-8"))
        source = data["source"]
        evidence = data["evidence"]
        assert data["schema"] == "grand-bruxelles-urbis-context-mesh-v1"
        assert source["provider"] == "Paradigm / Brussels-Capital Region"
        assert source["dataset"] == "UrbIS - 3D Constructions"
        assert source["building_2d_id"] == f"https://databrussels.be/id/building/{building_id}"
        assert source["crs"] == "EPSG:31370"
        assert source["license"] == "CC0-1.0"
        assert source["package_sha256"] == PACKAGE_SHA256
        assert source["details_level"] == 2
        assert evidence["triangle_count"] == contract["triangles"]
        assert evidence["face_count"] == 82
        assert data["runtime_approved"] is False
        assert len(data["faces"]) == evidence["face_count"]


def main() -> int:
    validate()
    # Causal regression: prove that deleting either production autoload is rejected.
    production = PROJECT.read_text(encoding="utf-8")
    for building_id, contract in EXPECTED.items():
        broken = production.replace(contract["autoload"], "")
        try:
            validate(broken)
        except AssertionError:
            continue
        raise AssertionError(f"regression did not reject missing official LoD2 mount {building_id}")
    print("GRAND_PLACE_OFFICIAL_LOD2_MOUNT_CONTRACT_OK buildings=1655673,1786758 source=UrbIS_LoD2 visual_acceptance=false jouable_authorized=false")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
