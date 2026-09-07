import copy
import json
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "data/source_plans/brussels_road_destination_factory_catalog.lock.json"
REGISTRY = ROOT / "data/source_plans/brussels_missing_road_source_registry.json"
EVIDENCE = ROOT / "data/source_plans/brussels_missing_road_source_acquisition_evidence.lock.json"
AUDERGHEM_EXPECTED = ROOT / "data/source_plans/auderghem_road_destination_index_expected.lock.json"

CATALOG_KEYS = {"schema", "derivation", "accounting", "municipalities"}
DERIVATION_KEYS = {"source_registry", "acquisition_evidence_lock", "rule"}
ACCOUNTING_KEYS = {
    "expected_municipalities",
    "acquired_artifact_locked",
    "remote_acquisition_unresolved",
    "road_identity_materialized",
    "cell_assignment_materialized",
}
MUNICIPALITY_KEYS = {
    "niscode",
    "id",
    "osm_relation_id",
    "source_status",
    "artifact_name",
    "source_file",
    "road_identity_status",
    "cell_status",
    "registration_authorized",
    "render_authorized",
    "collision_authorized",
    "runtime_ready",
    "jouable",
}


def reject_duplicate_object_keys(pairs: list[tuple[str, object]]) -> dict:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON object key: {key}")
        result[key] = value
    return result


def load(path: Path):
    return json.loads(
        path.read_text(encoding="utf-8"),
        object_pairs_hook=reject_duplicate_object_keys,
    )


def assert_catalog_schema_closed(catalog):
    assert set(catalog) == CATALOG_KEYS
    assert set(catalog["derivation"]) == DERIVATION_KEYS
    assert set(catalog["accounting"]) == ACCOUNTING_KEYS
    assert all(set(row) == MUNICIPALITY_KEYS for row in catalog["municipalities"])


def assert_catalog_accounting_non_bool_integers(accounting):
    for key in ACCOUNTING_KEYS:
        value = accounting[key]
        assert isinstance(value, int) and not isinstance(value, bool), key
        assert value >= 0, key


def test_catalog_loader_rejects_duplicate_object_keys(tmp_path: Path):
    ambiguous = tmp_path / "ambiguous-destination-catalog.lock.json"
    ambiguous.write_text(
        '{"accounting":{"road_identity_materialized":0,"road_identity_materialized":1077}}',
        encoding="utf-8",
    )
    with pytest.raises(ValueError, match="duplicate JSON object key: road_identity_materialized"):
        load(ambiguous)


def test_catalog_is_exact_locked_partition_and_fails_closed():
    catalog = load(CATALOG)
    registry = load(REGISTRY)
    evidence = load(EVIDENCE)

    assert_catalog_schema_closed(catalog)
    assert catalog["schema"] == "grand-bruxelles-road-destination-factory-catalog-v1"
    assert catalog["derivation"] == {
        "source_registry": "data/source_plans/brussels_missing_road_source_registry.json",
        "acquisition_evidence_lock": "data/source_plans/brussels_missing_road_source_acquisition_evidence.lock.json",
        "rule": "municipality readiness only; road identities/cells require materialized locked source artifacts",
    }
    rows = catalog["municipalities"]
    assert len(rows) == evidence["accounting"]["expected_municipalities"] == 16
    assert [row["niscode"] for row in rows] == [row["niscode"] for row in registry["municipalities"]]
    assert len({row["niscode"] for row in rows}) == 16

    locked = {row["niscode"]: row for row in evidence["successful_acquisitions"]}
    unresolved = {row["niscode"]: row for row in evidence["unresolved_acquisitions"]}
    assert set(locked) | set(unresolved) == {row["niscode"] for row in rows}
    assert set(locked).isdisjoint(unresolved)

    for row in rows:
        nis = row["niscode"]
        registry_row = next(item for item in registry["municipalities"] if item["niscode"] == nis)
        assert row["id"] == registry_row["id"]
        assert row["osm_relation_id"] == registry_row["osm_relation_id"]
        assert row["source_file"] is None
        assert row["cell_status"] == "NOT_ASSIGNED"
        assert row["registration_authorized"] is False
        assert row["render_authorized"] is False
        assert row["collision_authorized"] is False
        assert row["runtime_ready"] is False
        assert row["jouable"] is False

        if nis in locked:
            assert row["source_status"] == "ACQUIRED_ARTIFACT_LOCKED"
            assert row["artifact_name"] == locked[nis]["artifact"]["name"]
            assert row["road_identity_status"] == "NOT_MATERIALIZED_FROM_SOURCE_ARTIFACT"
        else:
            assert row["source_status"] == "REMOTE_ACQUISITION_UNRESOLVED"
            assert row["artifact_name"] is None
            assert row["road_identity_status"] == "SOURCE_UNRESOLVED"

    accounting = catalog["accounting"]
    assert_catalog_accounting_non_bool_integers(accounting)
    assert accounting == {
        "expected_municipalities": 16,
        "acquired_artifact_locked": len(locked),
        "remote_acquisition_unresolved": len(unresolved),
        "road_identity_materialized": 0,
        "cell_assignment_materialized": 0,
    }


def test_catalog_accounting_rejects_boolean_integer_aliases():
    catalog = load(CATALOG)
    mutations = []
    for key in ACCOUNTING_KEYS:
        mutated = copy.deepcopy(catalog)
        mutated["accounting"][key] = False
        mutations.append((key, mutated))

    for key, mutated in mutations:
        with pytest.raises(AssertionError, match=key):
            assert_catalog_accounting_non_bool_integers(mutated["accounting"])


def test_catalog_schema_rejects_unknown_readiness_or_accounting_fields():
    catalog = load(CATALOG)
    mutations = []

    root = copy.deepcopy(catalog)
    root["runtime_override"] = False
    mutations.append(root)

    derivation = copy.deepcopy(catalog)
    derivation["derivation"]["runtime_source"] = "forbidden"
    mutations.append(derivation)

    accounting = copy.deepcopy(catalog)
    accounting["accounting"]["jouable_materialized"] = 0
    mutations.append(accounting)

    municipality = copy.deepcopy(catalog)
    municipality["municipalities"][0]["collision_ready"] = False
    mutations.append(municipality)

    for mutated in mutations:
        try:
            assert_catalog_schema_closed(mutated)
        except AssertionError:
            continue
        raise AssertionError("catalog schema accepted an unknown field")


def test_auderghem_expected_index_fingerprint_is_evidence_bound_but_not_materialized():
    expected = load(AUDERGHEM_EXPECTED)
    evidence = load(EVIDENCE)
    catalog = load(CATALOG)
    locked = next(row for row in evidence["successful_acquisitions"] if row["niscode"] == "21002")
    catalog_row = next(row for row in catalog["municipalities"] if row["niscode"] == "21002")

    assert expected["schema"] == "grand-bruxelles-road-destination-index-expected-output-v1"
    assert expected["municipality"] == {key: locked[key] for key in ("niscode", "id", "name", "osm_relation_id")}
    source = expected["source"]
    assert source["provider"] == evidence["source"]["provider"]
    assert source["license"] == evidence["source"]["license"] == "ODbL-1.0"
    assert source["artifact_id"] == locked["artifact"]["id"] == 9741187457
    assert source["artifact_name"] == locked["artifact"]["name"]
    assert source["archive_sha256"] == locked["artifact"]["archive_sha256"]
    assert source["osm_base_timestamp"] == locked["osm_base_timestamp"]
    assert source["raw_snapshot_semantic_sha256"] == locked["raw_snapshot_semantic_sha256"]
    assert source["normalized_game_source_semantic_sha256"] == locked["normalized_game_source_semantic_sha256"]
    assert source["members"] == ["auderghem.manifest.json", "auderghem_road_source.raw.json", "auderghem_road_source.game.json", "auderghem_road_source.receipt.json"]

    assert expected["geometry"]["game_frame"] == evidence["game_frame"]
    assert expected["geometry"]["bounds_m"] == locked["bounds_m"]
    accounting = expected["accounting"]
    assert accounting["road_count"] == locked["road_count"] == 1077
    assert accounting["point_count"] == locked["point_count"] == 6715
    assert accounting["road_identity_materialized_in_expected_output"] == 1077
    for key in ("cell_assignment_materialized", "registered", "rendered", "collision_ready", "runtime_ready", "jouable"):
        assert accounting[key] == 0

    assert expected["expected_output"] == {
        "builder": "tools/city_machine/build_road_destination_index.py",
        "bytes": 505306,
        "sha256": "4c9b8fc0bc6c1951335da22d42ef84a5180a3f8bc853179536d9556cb8fb6ba2",
    }
    assert expected["repository_materialization"] == {"full_index_lock_present": False, "catalog_road_identity_materialized": 0}
    assert catalog["accounting"]["road_identity_materialized"] == 0
    assert catalog_row["source_file"] is None
    assert catalog_row["road_identity_status"] == "NOT_MATERIALIZED_FROM_SOURCE_ARTIFACT"
    assert catalog_row["cell_status"] == "NOT_ASSIGNED"
    for value in expected["authorization"].values():
        assert value is False
