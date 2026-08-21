#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "build_road_destination_catalog.py"
spec = importlib.util.spec_from_file_location("road_catalog", SCRIPT)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


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
        assert first["authorization"]["source_lookup_only"] is True
        assert first["authorization"]["jouable_authorized"] is False


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


def test_real_slice_contains_shipped_direct_entry_roads() -> None:
    catalog = module.build_catalog(ROOT / "data" / "osm")
    module.validate_contract(catalog)
    assert catalog["entry_count"] >= 140
    for osm_id in (359177328, 487501805, 1382734012):
        entry = catalog["entries"].get(str(osm_id))
        assert entry is not None, f"missing shipped direct-entry road {osm_id}"
        assert entry["drivable"] is True
        assert entry["point_count"] >= 2
        assert entry["name"].strip()
        assert entry["source_paths"] == sorted(entry["source_paths"])


def main() -> int:
    test_synthetic_determinism_and_duplicate_coalescing()
    test_conflicting_duplicate_fails_closed()
    test_real_slice_contains_shipped_direct_entry_roads()
    print("ROAD_DESTINATION_CATALOG_TEST_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
