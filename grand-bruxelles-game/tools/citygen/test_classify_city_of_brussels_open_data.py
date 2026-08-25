#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path

MODULE = Path(__file__).with_name("classify_city_of_brussels_open_data.py")
spec = importlib.util.spec_from_file_location("classify_city_open_data", MODULE)
assert spec and spec.loader
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def row(dataset_id: str, field_types: list[str], *, records=True, freq="DAILY", theme="Espace public"):
    return {
        "dataset_id": dataset_id,
        "has_records": records,
        "fields": [{"name": f"f{i}", "type": t} for i, t in enumerate(field_types)],
        "metas": {"default": {"title": dataset_id, "theme_fr": theme, "update_frequency": freq, "records_count": 3}},
    }


def snap(dataset_id: str, status="downloaded"):
    return {"dataset_id": dataset_id, "status": status}


def test_shape_beats_point_for_candidate_class() -> None:
    x = mod.classify_dataset(row("a", ["geo_point_2d", "geo_shape"]), snap("a"))
    assert x["game_inventory"]["candidate_class"] == "MAP_GEOMETRY_CANDIDATE"
    assert x["game_inventory"]["poi_candidate"] is True
    assert x["game_inventory"]["linear_or_area_candidate"] is True


def test_point_only_candidate() -> None:
    x = mod.classify_dataset(row("a", ["text", "geo_point_2d"]), snap("a"))
    assert x["game_inventory"]["candidate_class"] == "MAP_POI_CANDIDATE"


def test_non_geo_enrichment_candidate() -> None:
    x = mod.classify_dataset(row("a", ["text", "int"]), snap("a"))
    assert x["game_inventory"]["candidate_class"] == "DATA_ENRICHMENT_CANDIDATE"


def test_holds_override_geometry() -> None:
    x = mod.classify_dataset(row("a", ["geo_point_2d"]), snap("a", "metadata_only_federated_complete_export_unavailable"))
    assert x["game_inventory"]["candidate_class"] == "HOLD_SOURCE_UNAVAILABLE"
    assert x["game_inventory"]["poi_candidate"] is False


def test_no_records_hold() -> None:
    x = mod.classify_dataset(row("a", ["geo_point_2d"], records=False), snap("a", "metadata_only_no_records"))
    assert x["game_inventory"]["candidate_class"] == "HOLD_NO_RECORDS"


def test_realtime_is_objective_continuous_metadata_only() -> None:
    cont = mod.classify_dataset(row("a", ["geo_point_2d"], freq="CONT"), snap("a"))
    daily = mod.classify_dataset(row("b", ["geo_point_2d"], freq="DAILY"), snap("b"))
    assert cont["game_inventory"]["realtime_candidate"] is True
    assert daily["game_inventory"]["realtime_candidate"] is False


def test_summary_and_hard_rails() -> None:
    catalog = [
        row("a", ["geo_point_2d", "geo_shape"]),
        row("b", ["geo_point_2d"], freq="CONT"),
        row("c", ["text"]),
        row("d", ["geo_point_2d"], records=False),
    ]
    snapshot = {
        "schema": "grand-bruxelles-city-open-data-full-snapshot-index-v1",
        "catalog_sha256": "abc",
        "all_catalog_entries_accounted": True,
        "datasets": [snap("a"), snap("b"), snap("c"), snap("d", "metadata_only_no_records")],
    }
    out = mod.build_inventory(catalog, snapshot)
    assert out["summary"] == {
        "catalog_dataset_count": 4,
        "source_bytes_verified_count": 3,
        "geospatial_dataset_count": 3,
        "point_dataset_count": 3,
        "shape_dataset_count": 1,
        "continuous_geospatial_dataset_count": 1,
        "map_geometry_candidate_count": 1,
        "map_poi_candidate_count": 1,
        "data_enrichment_candidate_count": 1,
        "hold_count": 1,
    }
    assert out["authorization"]["classification_only"] is True
    for key in ["source_registration", "canonical_registration", "runtime_directory_scan", "runtime_mount", "rendered_geometry", "collision", "safe_spawn", "jouable_promotion"]:
        assert out["authorization"][key] is False


def test_compact_inventory_preserves_all_ids_and_rails() -> None:
    catalog = [row("a", ["geo_point_2d"]), row("b", ["text"])]
    snapshot = {
        "schema": "grand-bruxelles-city-open-data-full-snapshot-index-v1",
        "catalog_sha256": "abc",
        "all_catalog_entries_accounted": True,
        "datasets": [snap("a"), snap("b")],
    }
    full = mod.build_inventory(catalog, snapshot)
    compact = mod.compact_inventory(full)
    assert [x["dataset_id"] for x in compact["datasets"]] == ["a", "b"]
    assert compact["datasets"][0]["geospatial"] is True
    assert compact["authorization"] == full["authorization"]


def test_catalog_snapshot_identity_must_match() -> None:
    catalog = [row("a", ["text"])]
    snapshot = {
        "schema": "grand-bruxelles-city-open-data-full-snapshot-index-v1",
        "datasets": [snap("b")],
    }
    try:
        mod.build_inventory(catalog, snapshot)
    except ValueError:
        pass
    else:
        raise AssertionError("identity mismatch accepted")


def main() -> int:
    test_shape_beats_point_for_candidate_class()
    test_point_only_candidate()
    test_non_geo_enrichment_candidate()
    test_holds_override_geometry()
    test_no_records_hold()
    test_realtime_is_objective_continuous_metadata_only()
    test_summary_and_hard_rails()
    test_compact_inventory_preserves_all_ids_and_rails()
    test_catalog_snapshot_identity_must_match()
    print("CITY_OPEN_DATA_GAME_INVENTORY_TESTS_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
