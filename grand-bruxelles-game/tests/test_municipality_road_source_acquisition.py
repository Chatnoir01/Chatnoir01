from __future__ import annotations

import importlib.util
import json
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
TOOL = PROJECT / "tools/city_machine/acquire_municipality_road_source.py"
MANIFEST = PROJECT / "data/source_plans/auderghem_road_source_acquisition.json"


def load_tool():
    spec = importlib.util.spec_from_file_location("municipality_road_acquisition", TOOL)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_auderghem_manifest_targets_locked_relation_and_keeps_runtime_closed() -> None:
    module = load_tool()
    manifest = module.read_manifest(MANIFEST)
    assert manifest["municipality"] == {
        "niscode": "21002",
        "id": "auderghem",
        "name": "Auderghem / Oudergem",
        "osm_relation_id": 58263,
    }
    assert manifest["source"]["provider"] == "OpenStreetMap contributors via Overpass API"
    assert manifest["source"]["license"] == "ODbL-1.0"
    assert manifest["game_frame"]["origin_lat"] == 50.8419
    assert manifest["game_frame"]["origin_lon"] == 4.348
    assert manifest["authorization"]["source_acquisition_authorized"] is True
    for key in (
        "source_registration_authorized",
        "road_cell_mapping_authorized",
        "render_authorized",
        "collision_authorized",
        "runtime_mount_authorized",
        "safe_spawn_authorized",
        "jouable_authorized",
    ):
        assert manifest["authorization"][key] is False


def test_query_is_relation_scoped_and_drivable_only() -> None:
    module = load_tool()
    manifest = module.read_manifest(MANIFEST)
    query = module.build_query(manifest)
    assert "rel(58263);" in query
    assert "map_to_area->.municipality;" in query
    assert 'way(area.municipality)["highway"~"^(' in query
    assert "footway" not in query
    assert "cycleway" not in query
    assert "pedestrian" not in query
    assert "service" in query
    assert "residential" in query


def test_builder_rejects_open_runtime_authorization(tmp_path: Path) -> None:
    module = load_tool()
    payload = json.loads(MANIFEST.read_text(encoding="utf-8"))
    payload["authorization"]["runtime_mount_authorized"] = True
    modified = tmp_path / "manifest.json"
    modified.write_text(json.dumps(payload), encoding="utf-8")
    try:
        module.read_manifest(modified)
    except SystemExit as exc:
        assert "opened runtime_mount_authorized" in str(exc)
    else:
        raise AssertionError("open runtime authorization was accepted")


def test_normalization_keeps_acquired_source_unregistered() -> None:
    module = load_tool()
    manifest = module.read_manifest(MANIFEST)
    raw = {
        "osm3s": {"timestamp_osm_base": "2026-08-30T00:00:00Z"},
        "elements": [
            {
                "type": "way",
                "id": 123,
                "tags": {"highway": "residential", "name": "Teststraat"},
                "geometry": [
                    {"lat": 50.8420, "lon": 4.3480},
                    {"lat": 50.8421, "lon": 4.3482},
                ],
            }
        ],
    }
    game_source, receipt = module.build_outputs(manifest, raw)
    assert game_source["stats"]["roads"] == 1
    assert game_source["stats"]["drivable_roads"] == 1
    assert receipt["road_count"] == 1
    assert receipt["point_count"] == 2
    assert game_source["municipality"]["niscode"] == "21002"
    for key, value in game_source["authorization"].items():
        assert value is False, key
