from __future__ import annotations

import json
from pathlib import Path

import pytest

PROJECT = Path(__file__).resolve().parents[1]
REGISTRY = PROJECT / "data/source_plans/brussels_missing_road_source_registry.json"
TARGET = PROJECT / "data/qa/brussels_region_playability_target.json"

EXPECTED_MISSING = [
    "21002", "21003", "21005", "21006", "21007", "21008", "21009", "21010",
    "21011", "21012", "21014", "21015", "21016", "21017", "21018", "21019",
]
EXPECTED_REGISTERED = ["21001", "21004", "21013"]
EXPECTED_MUNICIPALITY_IDENTITIES = [
    ("21002", "auderghem", "Auderghem / Oudergem", 58263),
    ("21003", "berchem_sainte_agathe", "Berchem-Sainte-Agathe / Sint-Agatha-Berchem", 60140),
    ("21005", "etterbeek", "Etterbeek", 58252),
    ("21006", "evere", "Evere", 60144),
    ("21007", "forest", "Forest / Vorst", 58249),
    ("21008", "ganshoren", "Ganshoren", 58257),
    ("21009", "ixelles", "Ixelles / Elsene", 58250),
    ("21010", "jette", "Jette", 58258),
    ("21011", "koekelberg", "Koekelberg", 58256),
    ("21012", "molenbeek_saint_jean", "Molenbeek-Saint-Jean / Sint-Jans-Molenbeek", 58255),
    ("21014", "saint_josse_ten_noode", "Saint-Josse-ten-Noode / Sint-Joost-ten-Node", 58262),
    ("21015", "schaerbeek", "Schaerbeek / Schaarbeek", 58260),
    ("21016", "uccle", "Uccle / Ukkel", 58253),
    ("21017", "watermael_boitsfort", "Watermael-Boitsfort / Watermaal-Bosvoorde", 58264),
    ("21018", "woluwe_saint_lambert", "Woluwe-Saint-Lambert / Sint-Lambrechts-Woluwe", 60167),
    ("21019", "woluwe_saint_pierre", "Woluwe-Saint-Pierre / Sint-Pieters-Woluwe", 60168),
]
EXPECTED_TOP_LEVEL_KEYS = {"schema", "scope", "evidence_baseline", "source", "game_frame", "municipalities", "authorization"}
EXPECTED_EVIDENCE_BASELINE_KEYS = {"registered_niscodes", "missing_niscodes"}
EXPECTED_SOURCE_KEYS = {"provider", "license", "endpoint", "relation_reference"}
EXPECTED_MUNICIPALITY_KEYS = {"niscode", "id", "name", "osm_relation_id"}


def reject_duplicate_object_keys(pairs: list[tuple[str, object]]) -> dict:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON object key: {key}")
        result[key] = value
    return result


def load_json(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=reject_duplicate_object_keys)
    assert isinstance(value, dict)
    return value


def test_registry_loader_rejects_duplicate_object_keys(tmp_path: Path) -> None:
    ambiguous = tmp_path / "ambiguous-registry.json"
    ambiguous.write_text('{"authorization":{"runtime_mount_authorized":false,"runtime_mount_authorized":true}}', encoding="utf-8")
    with pytest.raises(ValueError, match="duplicate JSON object key: runtime_mount_authorized"):
        load_json(ambiguous)


def test_registry_schema_is_exact_and_rejects_undeclared_fields() -> None:
    registry = load_json(REGISTRY)
    assert set(registry) == EXPECTED_TOP_LEVEL_KEYS
    assert set(registry["evidence_baseline"]) == EXPECTED_EVIDENCE_BASELINE_KEYS
    assert set(registry["source"]) == EXPECTED_SOURCE_KEYS
    for row in registry["municipalities"]:
        assert set(row) == EXPECTED_MUNICIPALITY_KEYS, row.get("niscode")


def test_registry_partitions_exact_19_commune_target() -> None:
    registry = load_json(REGISTRY)
    target = load_json(TARGET)
    required = [row["niscode"] for row in target["required_municipalities"]]
    missing = registry["evidence_baseline"]["missing_niscodes"]
    registered = registry["evidence_baseline"]["registered_niscodes"]
    assert missing == EXPECTED_MISSING
    assert registered == EXPECTED_REGISTERED
    assert sorted(missing + registered) == sorted(required)
    assert len(set(missing + registered)) == 19


def test_registry_rows_match_missing_partition_exactly() -> None:
    registry = load_json(REGISTRY)
    rows = registry["municipalities"]
    assert [row["niscode"] for row in rows] == EXPECTED_MISSING
    assert len(rows) == 16
    assert len({row["id"] for row in rows}) == 16
    assert len({row["osm_relation_id"] for row in rows}) == 16
    assert all(isinstance(row["osm_relation_id"], int) and row["osm_relation_id"] > 0 for row in rows)


def test_registry_locks_exact_municipality_source_identity_crosswalk() -> None:
    rows = load_json(REGISTRY)["municipalities"]
    actual = [
        (row["niscode"], row["id"], row["name"], row["osm_relation_id"])
        for row in rows
    ]
    assert actual == EXPECTED_MUNICIPALITY_IDENTITIES


def test_registry_source_and_game_frame_are_locked() -> None:
    registry = load_json(REGISTRY)
    assert registry["schema"] == "grand-bruxelles-missing-road-source-registry-v1"
    assert registry["scope"] == "Brussels-Capital Region"
    assert registry["source"] == {
        "provider": "OpenStreetMap contributors via Overpass API",
        "license": "ODbL-1.0",
        "endpoint": "https://overpass-api.de/api/interpreter",
        "relation_reference": "OpenStreetMap WikiProject Belgium/Boundaries Brussels-Capital Region",
    }
    assert registry["game_frame"] == {"origin_lat": 50.8419,"origin_lon": 4.348,"axes": "X=east, Y=up, Z=south","units": "metres"}


def test_registry_only_authorizes_source_acquisition() -> None:
    authorization = load_json(REGISTRY)["authorization"]
    assert set(authorization) == {"source_acquisition_authorized","source_registration_authorized","road_cell_mapping_authorized","render_authorized","collision_authorized","runtime_mount_authorized","safe_spawn_authorized","jouable_authorized"}
    assert authorization["source_acquisition_authorized"] is True
    for key in ("source_registration_authorized","road_cell_mapping_authorized","render_authorized","collision_authorized","runtime_mount_authorized","safe_spawn_authorized","jouable_authorized"):
        assert authorization[key] is False, key
