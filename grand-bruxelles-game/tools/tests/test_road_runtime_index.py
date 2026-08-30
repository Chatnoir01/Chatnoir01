#!/usr/bin/env python3
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "build_road_runtime_index.py"
spec = importlib.util.spec_from_file_location("road_runtime_index", SCRIPT)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def write_lock(source_root: Path) -> None:
    repo_root = source_root.parent.parent
    documents = {
        path.relative_to(repo_root).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted(source_root.rglob("*.game.json"))
        if path.is_file()
    }
    (source_root / "road_destination_sources.lock.json").write_text(
        json.dumps({
            "format": "grand-bruxelles-road-destination-source-lock-v1",
            "source_format": "grand-bruxelles-osm-v1",
            "source": "OpenStreetMap contributors via Overpass API",
            "license": "ODbL-1.0",
            "evidence_artifact_id": 9733298021,
            "evidence_catalog_sha256": "786c9cbf3b420a658066bcdc809343abb463bd242b4aef432ab2c7975fa1baef",
            "documents": documents,
        }),
        encoding="utf-8",
    )


def write_document(path: Path, roads: list[dict]) -> str:
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(
        {"format": "grand-bruxelles-osm-v1", "roads": roads, "buildings": []},
        ensure_ascii=False,
    )
    path.write_text(text, encoding="utf-8")
    source_root = next(parent for parent in path.parents if parent.name == "osm" and parent.parent.name == "data")
    write_lock(source_root)
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def road(osm_id: int, name: str = "Teststraat - Rue Test") -> dict:
    return {
        "osm_id": osm_id,
        "name": name,
        "class": "tertiary",
        "width": 7.0,
        "drivable": True,
        "points": [[0.0, 0.0], [10.0, 0.0]],
    }


def assert_contract_rejects(index: dict, expected_fragment: str) -> None:
    try:
        module.validate_contract(index)
    except SystemExit as exc:
        assert expected_fragment in str(exc), str(exc)
    else:
        raise AssertionError(f"runtime index contract accepted invalid payload: {expected_fragment}")


def test_synthetic_determinism_and_source_binding() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        source_root = Path(tmp) / "data" / "osm"
        expected_sha = write_document(source_root / "slice.game.json", [road(20), road(10)])
        catalog = module._catalog_module.build_catalog(source_root)
        first = module.build_runtime_index(catalog)
        second = module.build_runtime_index(catalog)
        assert first == second
        assert first["format"] == "grand-bruxelles-road-runtime-index-v1"
        assert first["source_lookup_only"] is True
        assert first["authorization"]["safe_spawn_authorized"] is False
        assert len(first["documents"]) == 1
        descriptor = first["documents"][0]
        assert descriptor["path"] == "data/osm/slice.game.json"
        assert descriptor["sha256"] == expected_sha
        assert descriptor["road_ids"] == [10, 20]


def test_duplicate_source_ownership_fails_closed() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        source_root = Path(tmp) / "data" / "osm"
        write_document(source_root / "a.game.json", [road(42)])
        write_document(source_root / "b.game.json", [road(42)])
        catalog = module._catalog_module.build_catalog(source_root)
        try:
            module.build_runtime_index(catalog)
        except SystemExit as exc:
            assert "exactly one runtime source document" in str(exc)
        else:
            raise AssertionError("duplicate runtime source ownership did not fail closed")


def test_runtime_index_json_contract_fails_closed() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        source_root = Path(tmp) / "data" / "osm"
        write_document(source_root / "slice.game.json", [road(42)])
        catalog = module._catalog_module.build_catalog(source_root)
        index = module.build_runtime_index(catalog)

        injected = copy.deepcopy(index)
        injected["safe_spawn_ready"] = True
        assert_contract_rejects(injected, "field set drift")

        auth_injected = copy.deepcopy(index)
        auth_injected["authorization"]["rendered"] = True
        assert_contract_rejects(auth_injected, "authorization field set drift")

        descriptor_injected = copy.deepcopy(index)
        descriptor_injected["documents"][0]["municipality"] = "Bruxelles"
        assert_contract_rejects(descriptor_injected, "descriptor field set drift")

        string_road_id = copy.deepcopy(index)
        string_road_id["documents"][0]["road_ids"] = ["42"]
        assert_contract_rejects(string_road_id, "JSON type drift road id")

        string_sha = copy.deepcopy(index)
        string_sha["catalog_sha256"] = 42
        assert_contract_rejects(string_sha, "JSON type drift catalog_sha256")

        path_type_drift = copy.deepcopy(index)
        path_type_drift["documents"][0]["path"] = 42
        assert_contract_rejects(path_type_drift, "JSON type drift source path")

        parent_traversal = copy.deepcopy(index)
        parent_traversal["documents"][0]["path"] = "data/osm/../shadow.game.json"
        assert_contract_rejects(parent_traversal, "non-canonical source path")

        dot_segment = copy.deepcopy(index)
        dot_segment["documents"][0]["path"] = "data/osm/./slice.game.json"
        assert_contract_rejects(dot_segment, "non-canonical source path")

        backslash_drift = copy.deepcopy(index)
        backslash_drift["documents"][0]["path"] = "data/osm/sub\\slice.game.json"
        assert_contract_rejects(backslash_drift, "non-canonical source path")


def test_real_slice_matches_catalog_and_contains_lemonnier() -> None:
    source_root = ROOT / "data" / "osm"
    catalog = module._catalog_module.build_catalog(source_root)
    module._catalog_module.validate_contract(catalog)
    index = module.build_runtime_index(catalog)
    module.validate_contract(index)

    assert len(index["documents"]) == 1
    descriptor = index["documents"][0]
    assert descriptor["path"] == "data/osm/vertical_slice_01.game.json"
    assert descriptor["sha256"] == catalog["source_document_sha256"][descriptor["path"]]
    assert len(descriptor["road_ids"]) == catalog["entry_count"]
    assert 359177328 in descriptor["road_ids"]
    assert 487501805 in descriptor["road_ids"]
    assert 1382734012 in descriptor["road_ids"]
    assert index["catalog_sha256"] == catalog["catalog_sha256"]
    print(
        "ROAD_RUNTIME_INDEX_REAL_COUNT: "
        f"roads={len(descriptor['road_ids'])} documents={len(index['documents'])} "
        f"source_sha256={descriptor['sha256']} catalog_sha256={index['catalog_sha256']}"
    )


def main() -> int:
    test_synthetic_determinism_and_source_binding()
    test_duplicate_source_ownership_fails_closed()
    test_runtime_index_json_contract_fails_closed()
    test_real_slice_matches_catalog_and_contains_lemonnier()
    print("ROAD_RUNTIME_INDEX_TEST_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
