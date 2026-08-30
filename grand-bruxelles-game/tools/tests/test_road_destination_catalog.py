#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import json
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "build_road_destination_catalog.py"
LOCK_SCRIPT = ROOT / "tools" / "validate_road_destination_source_lock.py"
spec = importlib.util.spec_from_file_location("road_catalog", SCRIPT)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
lock_spec = importlib.util.spec_from_file_location("road_source_lock", LOCK_SCRIPT)
assert lock_spec and lock_spec.loader
lock_module = importlib.util.module_from_spec(lock_spec)
lock_spec.loader.exec_module(lock_module)


def write_document(path: Path, roads: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps({"format": "grand-bruxelles-osm-v1", "roads": roads, "buildings": []}),
        encoding="utf-8",
    )


def road(osm_id: int, name: str = "Teststraat - Rue Test") -> dict:
    return {
        "osm_id": osm_id,
        "name": name,
        "class": "tertiary",
        "width": 7.0,
        "drivable": True,
        "points": [[0.0, 0.0], [10.0, 0.0]],
    }


def write_lock(root: Path, documents: dict[str, str]) -> Path:
    lock_path = root / "road_destination_sources.lock.json"
    lock_path.write_text(
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
    return lock_path


def test_synthetic_determinism_and_duplicate_coalescing() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp) / "data" / "osm"
        write_document(root / "b.game.json", [road(20), road(10)])
        write_document(root / "nested" / "a.game.json", [road(10)])
        first = module.build_catalog(root)
        second = module.build_catalog(root)
        assert module.canonical_json(first) == module.canonical_json(second)
        assert list(first["entries"]) == ["10", "20"]
        assert first["entries"]["10"]["source_file_count"] == 2
        assert first["drivable_record_count"] == 3
        assert first["eligible_record_count"] == 3
        assert first["rejected_drivable_record_count"] == 0
        assert first["entry_count"] == 2
        assert first["duplicate_record_count"] == 1
        assert first["authorization"]["source_lookup_only"] is True
        assert first["authorization"]["jouable_authorized"] is False


def test_locked_source_selection_ignores_unlisted_compatible_documents() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp) / "data" / "osm"
        listed = root / "listed.game.json"
        write_document(listed, [road(10, "Locked Rue")])
        write_document(root / "mutable-extra.game.json", [road(20, "Unlisted Rue")])
        locked = {"data/osm/listed.game.json": hashlib.sha256(listed.read_bytes()).hexdigest()}
        lock_path = write_lock(root, locked)
        try:
            lock_module.validate(root, lock_path)
        except SystemExit as exc:
            assert "compatible source set drift" in str(exc)
            assert "mutable-extra.game.json" in str(exc)
        else:
            raise AssertionError("unlisted compatible source document was accepted")


def test_locked_source_selection_rejects_digest_drift() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp) / "data" / "osm"
        listed = root / "listed.game.json"
        write_document(listed, [road(10, "Locked Rue")])
        lock_path = write_lock(root, {"data/osm/listed.game.json": "0" * 64})
        try:
            lock_module.validate(root, lock_path)
        except SystemExit as exc:
            assert "locked source document SHA256 drift" in str(exc)
        else:
            raise AssertionError("locked source digest drift did not fail closed")


def test_drivable_without_lookup_identity_is_rejected_explicitly() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp) / "data" / "osm"
        unnamed = road(30, "")
        write_document(root / "a.game.json", [road(20), unnamed])
        catalog = module.build_catalog(root)
        module.validate_contract(catalog)
        assert catalog["drivable_record_count"] == 2
        assert catalog["eligible_record_count"] == 1
        assert catalog["rejected_drivable_record_count"] == 1
        assert catalog["entry_count"] == 1
        assert "30" not in catalog["entries"]


def test_conflicting_duplicate_fails_closed() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp) / "data" / "osm"
        write_document(root / "a.game.json", [road(42, "Rue A")])
        write_document(root / "b.game.json", [road(42, "Rue B")])
        try:
            module.build_catalog(root)
        except SystemExit as exc:
            assert "conflicting duplicate OSM road 42" in str(exc)
        else:
            raise AssertionError("conflicting duplicate OSM road did not fail closed")


def test_source_json_numeric_identity_types_fail_closed() -> None:
    mutations = (
        ("osm_id", lambda payload: payload.__setitem__("osm_id", str(payload["osm_id"]))),
        ("point_x", lambda payload: payload["points"][0].__setitem__(0, str(payload["points"][0][0]))),
        ("width", lambda payload: payload.__setitem__("width", str(payload["width"]))),
    )
    for label, mutate in mutations:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "data" / "osm"
            changed = road(42, "Rue A")
            mutate(changed)
            write_document(root / f"{label}.game.json", [changed])
            try:
                module.build_catalog(root)
            except SystemExit as exc:
                assert "source JSON type drift" in str(exc)
            else:
                raise AssertionError(f"numeric-string source {label} was normalized instead of rejected")


def test_catalog_semantic_tamper_fails_closed() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp) / "data" / "osm"
        write_document(root / "a.game.json", [road(42, "Rue A")])
        catalog = module.build_catalog(root)
        tampered = json.loads(json.dumps(catalog))
        tampered["entries"]["42"]["name"] = "Rue B"
        try:
            module.validate_contract(tampered)
        except SystemExit as exc:
            assert "catalog SHA256 drift" in str(exc)
        else:
            raise AssertionError("semantic catalog tamper did not fail closed")


def test_source_path_must_bind_to_locked_document_digest() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp) / "data" / "osm"
        write_document(root / "a.game.json", [road(42, "Rue A")])
        catalog = module.build_catalog(root)
        tampered = json.loads(json.dumps(catalog))
        entry = tampered["entries"]["42"]
        entry["source_paths"] = ["data/osm/missing.game.json"]
        entry["source_file_count"] = 1
        unsigned = dict(tampered)
        unsigned.pop("catalog_sha256", None)
        tampered["catalog_sha256"] = module.sha256_text(module.canonical_json(unsigned))
        try:
            module.validate_contract(tampered)
        except SystemExit as exc:
            assert "source path missing locked digest" in str(exc)
        else:
            raise AssertionError("unbound source path did not fail closed")


def test_catalog_must_rebind_to_locked_source_geometry() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp) / "data" / "osm"
        source_path = root / "a.game.json"
        write_document(source_path, [road(42, "Rue A")])
        catalog = module.build_catalog(root)
        module.validate_source_binding(catalog, root)
        changed = road(42, "Rue A")
        changed["points"] = [[0.0, 0.0], [20.0, 0.0]]
        write_document(source_path, [changed])
        try:
            module.validate_source_binding(catalog, root)
        except SystemExit as exc:
            assert "source binding drift" in str(exc)
        else:
            raise AssertionError("source geometry drift did not fail closed")


def test_real_slice_contains_shipped_direct_entry_roads() -> None:
    locked = lock_module.validate(ROOT / "data" / "osm")
    assert locked == {
        "data/osm/vertical_slice_01.game.json":
        "899bc73ee0eea3623d7cc45455a542c1704039ef0239c13c33b3c74b4a241398"
    }
    catalog = module.build_catalog(ROOT / "data" / "osm")
    module.validate_contract(catalog)
    module.validate_source_binding(catalog, ROOT / "data" / "osm")
    assert catalog["source_document_sha256"] == locked
    print(
        "ROAD_DESTINATION_CATALOG_REAL_COUNT: "
        f"entries={catalog['entry_count']} drivable_records={catalog['drivable_record_count']} "
        f"eligible_records={catalog['eligible_record_count']} "
        f"rejected_drivable={catalog['rejected_drivable_record_count']} "
        f"duplicate_records={catalog['duplicate_record_count']} documents={catalog['compatible_document_count']}"
    )
    assert catalog["road_record_count"] == 140
    assert catalog["drivable_record_count"] == 140
    assert catalog["eligible_record_count"] == 139
    assert catalog["rejected_drivable_record_count"] == 1
    assert catalog["entry_count"] == 139
    assert catalog["duplicate_record_count"] == 0
    assert catalog["compatible_document_count"] == 1
    for osm_id in (359177328, 487501805, 1382734012):
        entry = catalog["entries"].get(str(osm_id))
        assert entry is not None, f"missing shipped direct-entry road {osm_id}"
        assert entry["drivable"] is True
        assert entry["point_count"] >= 2
        assert entry["name"].strip()
        assert entry["source_paths"] == sorted(entry["source_paths"])


def main() -> int:
    test_synthetic_determinism_and_duplicate_coalescing()
    test_locked_source_selection_ignores_unlisted_compatible_documents()
    test_locked_source_selection_rejects_digest_drift()
    test_drivable_without_lookup_identity_is_rejected_explicitly()
    test_conflicting_duplicate_fails_closed()
    test_source_json_numeric_identity_types_fail_closed()
    test_catalog_semantic_tamper_fails_closed()
    test_source_path_must_bind_to_locked_document_digest()
    test_catalog_must_rebind_to_locked_source_geometry()
    test_real_slice_contains_shipped_direct_entry_roads()
    print("ROAD_DESTINATION_CATALOG_TEST_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
