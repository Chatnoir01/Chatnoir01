from __future__ import annotations

import importlib.util
import json
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
TOOL = PROJECT / "tools/city_machine/acquire_municipality_road_source.py"
MANIFEST = PROJECT / "data/source_plans/auderghem_road_source_acquisition.json"
REGISTRY = PROJECT / "data/source_plans/brussels_missing_road_source_registry.json"


def load_tool():
    spec = importlib.util.spec_from_file_location("municipality_road_acquisition", TOOL)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module); return module


def test_auderghem_manifest_targets_locked_relation_and_keeps_runtime_closed() -> None:
    module = load_tool(); manifest = module.read_manifest(MANIFEST)
    assert manifest["municipality"] == {"niscode": "21002", "id": "auderghem", "name": "Auderghem / Oudergem", "osm_relation_id": 58263}
    assert manifest["source"]["provider"] == "OpenStreetMap contributors via Overpass API"
    assert manifest["source"]["license"] == "ODbL-1.0"
    assert manifest["game_frame"]["origin_lat"] == 50.8419 and manifest["game_frame"]["origin_lon"] == 4.348
    assert manifest["authorization"]["source_acquisition_authorized"] is True
    for key in ("source_registration_authorized","road_cell_mapping_authorized","render_authorized","collision_authorized","runtime_mount_authorized","safe_spawn_authorized","jouable_authorized"): assert manifest["authorization"][key] is False


def test_query_is_relation_scoped_and_drivable_only() -> None:
    module = load_tool(); manifest = module.read_manifest(MANIFEST); query = module.build_query(manifest)
    assert "rel(58263);" in query and "map_to_area->.municipality;" in query and 'way(area.municipality)["highway"~"^(' in query
    assert "footway" not in query and "cycleway" not in query and "pedestrian" not in query
    assert "service" in query and "residential" in query


def test_builder_rejects_open_runtime_authorization(tmp_path: Path) -> None:
    module = load_tool(); payload = json.loads(MANIFEST.read_text(encoding="utf-8")); payload["authorization"]["runtime_mount_authorized"] = True
    modified = tmp_path / "manifest.json"; modified.write_text(json.dumps(payload), encoding="utf-8")
    try: module.read_manifest(modified)
    except SystemExit as exc: assert "opened runtime_mount_authorized" in str(exc)
    else: raise AssertionError("open runtime authorization was accepted")


def test_builder_rejects_undeclared_authorization_keys(tmp_path: Path) -> None:
    module = load_tool(); payload = json.loads(MANIFEST.read_text(encoding="utf-8")); payload["authorization"]["collision_ready"] = True
    modified = tmp_path / "manifest-unknown-authorization.json"; modified.write_text(json.dumps(payload), encoding="utf-8")
    try: module.read_manifest(modified)
    except SystemExit as exc: assert "unexpected manifest authorization keys" in str(exc)
    else: raise AssertionError("undeclared authorization key was silently accepted")


def test_manifest_rejects_duplicate_json_keys_recursively(tmp_path: Path) -> None:
    module = load_tool(); raw = MANIFEST.read_text(encoding="utf-8").replace('"runtime_mount_authorized": false,','"runtime_mount_authorized": true,\n    "runtime_mount_authorized": false,',1)
    modified = tmp_path / "duplicate-key-manifest.json"; modified.write_text(raw, encoding="utf-8")
    try: module.read_manifest(modified)
    except SystemExit as exc: assert "duplicate JSON object key runtime_mount_authorized" in str(exc)
    else: raise AssertionError("duplicate JSON manifest key was silently accepted")


def test_manifest_rejects_source_identity_drift(tmp_path: Path) -> None:
    module = load_tool(); payload = json.loads(MANIFEST.read_text(encoding="utf-8")); payload["source"]["endpoint"] = "https://example.invalid/overpass"
    modified = tmp_path / "manifest-source-drift.json"; modified.write_text(json.dumps(payload), encoding="utf-8")
    try: module.read_manifest(modified)
    except SystemExit as exc: assert "manifest source identity drift" in str(exc)
    else: raise AssertionError("manifest source endpoint drift was silently accepted")


def test_manifest_rejects_game_frame_drift(tmp_path: Path) -> None:
    module = load_tool(); payload = json.loads(MANIFEST.read_text(encoding="utf-8")); payload["game_frame"]["origin_lon"] = 4.5
    modified = tmp_path / "manifest-frame-drift.json"; modified.write_text(json.dumps(payload), encoding="utf-8")
    try: module.read_manifest(modified)
    except SystemExit as exc: assert "manifest game frame drift" in str(exc)
    else: raise AssertionError("manifest game-frame drift was silently accepted")


def test_registry_manifest_builder_is_strict_and_preserves_locked_identity(tmp_path: Path) -> None:
    module = load_tool(); registry = module.read_registry(REGISTRY); manifest = module.build_manifest_from_registry(registry, "21002", "auderghem")
    assert manifest["schema"] == module.SCHEMA and manifest["municipality"]["osm_relation_id"] == 58263
    assert manifest["source"]["provider"] == "OpenStreetMap contributors via Overpass API" and manifest["source"]["license"] == "ODbL-1.0"
    assert manifest["authorization"]["runtime_mount_authorized"] is False
    raw = REGISTRY.read_text(encoding="utf-8").replace('"runtime_mount_authorized": false,','"runtime_mount_authorized": true,\n    "runtime_mount_authorized": false,',1)
    duplicate = tmp_path / "duplicate-key-registry.json"; duplicate.write_text(raw, encoding="utf-8")
    try: module.read_registry(duplicate)
    except SystemExit as exc: assert "duplicate JSON object key runtime_mount_authorized" in str(exc)
    else: raise AssertionError("duplicate JSON registry key was silently accepted")


def test_registry_rejects_undeclared_authorization_keys(tmp_path: Path) -> None:
    module = load_tool(); payload = json.loads(REGISTRY.read_text(encoding="utf-8")); payload["authorization"]["registered"] = True
    modified = tmp_path / "registry-unknown-authorization.json"; modified.write_text(json.dumps(payload), encoding="utf-8")
    try: module.read_registry(modified)
    except SystemExit as exc: assert "unexpected registry authorization keys" in str(exc)
    else: raise AssertionError("undeclared registry authorization key was silently accepted")


def test_registry_rejects_evidence_baseline_drift(tmp_path: Path) -> None:
    module = load_tool(); payload = json.loads(REGISTRY.read_text(encoding="utf-8")); payload["evidence_baseline"]["missing_niscodes"] = payload["evidence_baseline"]["missing_niscodes"][:-1]
    modified = tmp_path / "registry-accounting-drift.json"; modified.write_text(json.dumps(payload), encoding="utf-8")
    try: module.read_registry(modified)
    except SystemExit as exc: assert "registry evidence baseline drift" in str(exc)
    else: raise AssertionError("registry evidence accounting drift was silently accepted")


def test_registry_rejects_municipality_relation_identity_drift(tmp_path: Path) -> None:
    module = load_tool(); payload = json.loads(REGISTRY.read_text(encoding="utf-8")); payload["municipalities"][0]["osm_relation_id"] = 999999999
    modified = tmp_path / "registry-municipality-drift.json"; modified.write_text(json.dumps(payload), encoding="utf-8")
    try: module.read_registry(modified)
    except SystemExit as exc: assert "registry municipality identity drift" in str(exc)
    else: raise AssertionError("registry municipality relation drift was silently accepted")


def test_manifest_rejects_unregistered_municipality_identity(tmp_path: Path) -> None:
    module = load_tool(); payload = json.loads(MANIFEST.read_text(encoding="utf-8")); payload["municipality"]["osm_relation_id"] = 999999999
    modified = tmp_path / "manifest-municipality-drift.json"; modified.write_text(json.dumps(payload), encoding="utf-8")
    try: module.read_manifest(modified)
    except SystemExit as exc: assert "manifest municipality identity drift" in str(exc)
    else: raise AssertionError("direct manifest municipality relation drift was silently accepted")


def test_normalization_rejects_missing_osm_base_timestamp() -> None:
    module = load_tool(); manifest = module.read_manifest(MANIFEST)
    raw = {"osm3s": {}, "elements": [{"type": "way", "id": 123, "tags": {"highway": "residential", "name": "Teststraat"}, "geometry": [{"lat": 50.8420, "lon": 4.3480}, {"lat": 50.8421, "lon": 4.3482}]}]}
    try: module.build_outputs(manifest, raw)
    except SystemExit as exc: assert "missing OSM base timestamp" in str(exc)
    else: raise AssertionError("source without OSM base timestamp produced lockable outputs")


def test_normalization_keeps_acquired_source_unregistered() -> None:
    module = load_tool(); manifest = module.read_manifest(MANIFEST)
    raw = {"osm3s": {"timestamp_osm_base": "2026-08-30T00:00:00Z"}, "elements": [{"type": "way", "id": 123, "tags": {"highway": "residential", "name": "Teststraat"}, "geometry": [{"lat": 50.8420, "lon": 4.3480}, {"lat": 50.8421, "lon": 4.3482}]}]}
    game_source, receipt = module.build_outputs(manifest, raw)
    assert game_source["stats"]["roads"] == 1 and game_source["stats"]["drivable_roads"] == 1
    assert receipt["road_count"] == 1 and receipt["point_count"] == 2 and game_source["municipality"]["niscode"] == "21002"
    for key, value in game_source["authorization"].items(): assert value is False, key


def test_normalization_rejects_coerced_drivable_road_count() -> None:
    module = load_tool(); manifest = module.read_manifest(MANIFEST)
    raw = {"osm3s": {"timestamp_osm_base": "2026-08-30T00:00:00Z"}, "elements": [{"type": "way", "id": 123, "tags": {"highway": "residential"}, "geometry": [{"lat": 50.8420, "lon": 4.3480}, {"lat": 50.8421, "lon": 4.3482}]}]}
    road = {"osm_id": 123, "class": "residential", "drivable": True, "points": [[0.0, 0.0], [1.0, 1.0]]}
    for invalid_count in (True, 1.5, "1"):
        module.convert = lambda _raw, _origin, value=invalid_count: {"roads": [road], "stats": {"roads": 1, "drivable_roads": value}}
        try: module.build_outputs(manifest, raw)
        except SystemExit as exc: assert "invalid normalized drivable road count" in str(exc)
        else: raise AssertionError(f"coerced drivable road count {invalid_count!r} was accepted")
