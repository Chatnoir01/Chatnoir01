from __future__ import annotations

import copy
import json
import math
import re
from pathlib import Path

import pytest

PROJECT = Path(__file__).resolve().parents[1]
EXPECTED_LOCK = PROJECT / "data/source_plans/auderghem_road_destination_index_expected.lock.json"

ROOT_KEYS = {
    "schema", "municipality", "source", "geometry", "accounting",
    "expected_output", "repository_materialization", "authorization",
}
MUNICIPALITY_KEYS = {"niscode", "id", "name", "osm_relation_id"}
SOURCE_KEYS = {
    "provider", "license", "artifact_id", "artifact_name", "archive_sha256",
    "osm_base_timestamp", "raw_snapshot_semantic_sha256",
    "normalized_game_source_semantic_sha256", "members",
}
GEOMETRY_KEYS = {"game_frame", "bounds_m"}
GAME_FRAME_KEYS = {"origin_lat", "origin_lon", "axes", "units"}
ACCOUNTING_KEYS = {
    "road_count", "point_count", "road_identity_materialized_in_expected_output",
    "cell_assignment_materialized", "registered", "rendered", "collision_ready",
    "runtime_ready", "jouable",
}
EXPECTED_OUTPUT_KEYS = {"builder", "bytes", "sha256"}
REPOSITORY_MATERIALIZATION_KEYS = {
    "full_index_lock_present", "catalog_road_identity_materialized",
}
AUTHORIZATION_KEYS = {
    "source_registration_authorized", "road_cell_mapping_authorized",
    "render_authorized", "collision_authorized", "runtime_mount_authorized",
    "safe_spawn_authorized", "jouable_authorized",
}
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
EXPECTED_SCHEMA = "grand-bruxelles-road-destination-index-expected-output-v1"
EXPECTED_ARTIFACT_ID = 9741187457
EXPECTED_ARCHIVE_SHA256 = "f360fdf727914518c626f01509cebb1d0e4fca765d7bc08142b10a967c56ff5c"
EXPECTED_OSM_BASE_TIMESTAMP = "2026-08-30T23:58:06Z"
EXPECTED_RAW_SHA256 = "efd7724ae9198e1716d689ed94cbb39e917827d6912f60465b69ad8c547bcd8a"
EXPECTED_NORMALIZED_SHA256 = "ec69972237059dc3ba492d6ebd1242b2c770d27c1ca1d8b2937ec8cb67fab2fe"
EXPECTED_MEMBERS = [
    "auderghem.manifest.json",
    "auderghem_road_source.raw.json",
    "auderghem_road_source.game.json",
    "auderghem_road_source.receipt.json",
]
EXPECTED_BOUNDS_M = [3332.77, 1373.9, 9821.48, 6507.9]
EXPECTED_INDEX_SHA256 = "4c9b8fc0bc6c1951335da22d42ef84a5180a3f8bc853179536d9556cb8fb6ba2"


def reject_duplicate_object_keys(pairs: list[tuple[str, object]]) -> dict:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON object key: {key}")
        result[key] = value
    return result


def load_lock(path: Path = EXPECTED_LOCK) -> dict:
    value = json.loads(
        path.read_text(encoding="utf-8"),
        object_pairs_hook=reject_duplicate_object_keys,
    )
    assert isinstance(value, dict)
    return value


def assert_exact_schema(lock: dict) -> None:
    assert set(lock) == ROOT_KEYS
    assert set(lock["municipality"]) == MUNICIPALITY_KEYS
    assert set(lock["source"]) == SOURCE_KEYS
    assert set(lock["geometry"]) == GEOMETRY_KEYS
    assert set(lock["geometry"]["game_frame"]) == GAME_FRAME_KEYS
    assert set(lock["accounting"]) == ACCOUNTING_KEYS
    assert set(lock["expected_output"]) == EXPECTED_OUTPUT_KEYS
    assert set(lock["repository_materialization"]) == REPOSITORY_MATERIALIZATION_KEYS
    assert set(lock["authorization"]) == AUTHORIZATION_KEYS


def assert_value_domains(lock: dict) -> None:
    assert lock["schema"] == EXPECTED_SCHEMA

    municipality = lock["municipality"]
    assert municipality["niscode"] == "21002"
    assert municipality["id"] == "auderghem"
    assert municipality["name"] == "Auderghem / Oudergem"
    assert type(municipality["osm_relation_id"]) is int
    assert municipality["osm_relation_id"] == 58263

    source = lock["source"]
    assert source["provider"] == "OpenStreetMap contributors via Overpass API"
    assert source["license"] == "ODbL-1.0"
    assert type(source["artifact_id"]) is int
    assert source["artifact_id"] == EXPECTED_ARTIFACT_ID
    assert source["artifact_name"] == "road-source-21002-auderghem"
    for field in (
        "archive_sha256",
        "raw_snapshot_semantic_sha256",
        "normalized_game_source_semantic_sha256",
    ):
        assert isinstance(source[field], str) and SHA256_RE.fullmatch(source[field])
    assert source["archive_sha256"] == EXPECTED_ARCHIVE_SHA256
    assert source["osm_base_timestamp"] == EXPECTED_OSM_BASE_TIMESTAMP
    assert source["raw_snapshot_semantic_sha256"] == EXPECTED_RAW_SHA256
    assert source["normalized_game_source_semantic_sha256"] == EXPECTED_NORMALIZED_SHA256
    assert source["members"] == EXPECTED_MEMBERS

    game_frame = lock["geometry"]["game_frame"]
    for field in ("origin_lat", "origin_lon"):
        value = game_frame[field]
        assert type(value) in (int, float) and math.isfinite(value)
    assert game_frame["origin_lat"] == 50.8419
    assert game_frame["origin_lon"] == 4.348
    assert game_frame["axes"] == "X=east, Y=up, Z=south"
    assert game_frame["units"] == "metres"

    bounds = lock["geometry"]["bounds_m"]
    assert isinstance(bounds, list) and len(bounds) == 4
    assert all(type(value) in (int, float) and math.isfinite(value) for value in bounds)
    min_x, min_z, max_x, max_z = bounds
    assert min_x < max_x and min_z < max_z
    assert bounds == EXPECTED_BOUNDS_M

    accounting = lock["accounting"]
    for field in ACCOUNTING_KEYS:
        assert type(accounting[field]) is int and accounting[field] >= 0
    assert accounting["road_count"] == 1077
    assert accounting["point_count"] == 6715
    assert accounting["road_identity_materialized_in_expected_output"] == accounting["road_count"]
    for field in (
        "cell_assignment_materialized", "registered", "rendered", "collision_ready",
        "runtime_ready", "jouable",
    ):
        assert accounting[field] == 0

    expected_output = lock["expected_output"]
    assert expected_output["builder"] == "tools/city_machine/build_road_destination_index.py"
    assert type(expected_output["bytes"]) is int and expected_output["bytes"] == 505306
    assert isinstance(expected_output["sha256"], str) and SHA256_RE.fullmatch(expected_output["sha256"])
    assert expected_output["sha256"] == EXPECTED_INDEX_SHA256

    materialization = lock["repository_materialization"]
    assert materialization["full_index_lock_present"] is False
    assert type(materialization["catalog_road_identity_materialized"]) is int
    assert materialization["catalog_road_identity_materialized"] == 0

    authorization = lock["authorization"]
    assert all(value is False for value in authorization.values())


def test_auderghem_expected_index_lock_loader_rejects_duplicate_object_keys(tmp_path: Path) -> None:
    ambiguous = tmp_path / "ambiguous-auderghem-expected.lock.json"
    ambiguous.write_text(
        '{"authorization":{"jouable_authorized":false,"jouable_authorized":true}}',
        encoding="utf-8",
    )
    with pytest.raises(ValueError, match="duplicate JSON object key: jouable_authorized"):
        load_lock(ambiguous)


def test_auderghem_expected_index_lock_schema_is_closed() -> None:
    lock = load_lock()
    assert_exact_schema(lock)
    assert_value_domains(lock)


@pytest.mark.parametrize(
    ("container_path", "unknown_key"),
    [
        ((), "unexpected_root"),
        (("municipality",), "unexpected_municipality"),
        (("source",), "unexpected_source"),
        (("geometry",), "unexpected_geometry"),
        (("geometry", "game_frame"), "unexpected_game_frame"),
        (("accounting",), "unexpected_accounting"),
        (("expected_output",), "unexpected_expected_output"),
        (("repository_materialization",), "unexpected_materialization"),
        (("authorization",), "unexpected_authorization"),
    ],
)
def test_auderghem_expected_index_lock_rejects_unknown_keys(
    container_path: tuple[str, ...], unknown_key: str
) -> None:
    mutated = copy.deepcopy(load_lock())
    container = mutated
    for key in container_path:
        container = container[key]
    container[unknown_key] = "must-fail-closed"
    with pytest.raises(AssertionError):
        assert_exact_schema(mutated)


@pytest.mark.parametrize(
    ("path", "bad_value"),
    [
        (("accounting", "road_count"), False),
        (("accounting", "point_count"), True),
        (("expected_output", "bytes"), False),
        (("repository_materialization", "catalog_road_identity_materialized"), False),
        (("authorization", "jouable_authorized"), True),
        (("geometry", "bounds_m"), [3332.77, 1373.9, 3332.77, 6507.9]),
        (("source", "archive_sha256"), "not-a-sha256"),
    ],
)
def test_auderghem_expected_index_lock_rejects_invalid_value_domains(
    path: tuple[str, ...], bad_value: object
) -> None:
    mutated = copy.deepcopy(load_lock())
    container = mutated
    for key in path[:-1]:
        container = container[key]
    container[path[-1]] = bad_value
    with pytest.raises(AssertionError):
        assert_value_domains(mutated)


@pytest.mark.parametrize(
    ("path", "drifted_value"),
    [
        (("source", "artifact_id"), 9741187458),
        (("source", "archive_sha256"), "0" * 64),
        (("source", "osm_base_timestamp"), "2026-08-31T23:58:06Z"),
        (("source", "raw_snapshot_semantic_sha256"), "1" * 64),
        (("source", "normalized_game_source_semantic_sha256"), "2" * 64),
        (("source", "members"), ["a.json", "b.json", "c.json", "d.json"]),
        (("expected_output", "sha256"), "3" * 64),
        (("geometry", "bounds_m"), [3332.78, 1373.9, 9821.48, 6507.9]),
    ],
)
def test_auderghem_expected_index_lock_rejects_validly_typed_provenance_drift(
    path: tuple[str, ...], drifted_value: object
) -> None:
    mutated = copy.deepcopy(load_lock())
    container = mutated
    for key in path[:-1]:
        container = container[key]
    container[path[-1]] = drifted_value
    with pytest.raises(AssertionError):
        assert_value_domains(mutated)
