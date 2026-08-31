from __future__ import annotations

import json
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
REGISTRY = PROJECT / "data/source_plans/brussels_missing_road_source_registry.json"
TARGET = PROJECT / "data/qa/brussels_region_playability_target.json"

EXPECTED_MISSING = [
    "21002", "21003", "21005", "21006", "21007", "21008", "21009", "21010",
    "21011", "21012", "21014", "21015", "21016", "21017", "21018", "21019",
]
EXPECTED_REGISTERED = ["21001", "21004", "21013"]


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


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


def test_registry_source_and_game_frame_are_locked() -> None:
    registry = load_json(REGISTRY)
    assert registry["schema"] == "grand-bruxelles-missing-road-source-registry-v1"
    assert registry["scope"] == "Brussels-Capital Region"
    assert registry["source"]["provider"] == "OpenStreetMap contributors via Overpass API"
    assert registry["source"]["license"] == "ODbL-1.0"
    assert registry["source"]["endpoint"] == "https://overpass-api.de/api/interpreter"
    assert registry["game_frame"] == {
        "origin_lat": 50.8419,
        "origin_lon": 4.348,
        "axes": "X=east, Y=up, Z=south",
        "units": "metres",
    }


def test_registry_only_authorizes_source_acquisition() -> None:
    authorization = load_json(REGISTRY)["authorization"]
    assert authorization["source_acquisition_authorized"] is True
    for key in (
        "source_registration_authorized",
        "road_cell_mapping_authorized",
        "render_authorized",
        "collision_authorized",
        "runtime_mount_authorized",
        "safe_spawn_authorized",
        "jouable_authorized",
    ):
        assert authorization[key] is False, key
