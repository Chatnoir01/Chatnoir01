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


def write_document(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(
            {
                "format": "grand-bruxelles-osm-v1",
                "roads": [
                    {
                        "osm_id": 42,
                        "name": "Rue Test",
                        "class": "tertiary",
                        "width": 7.0,
                        "drivable": True,
                        "points": [[0.0, 0.0], [10.0, 0.0]],
                    }
                ],
                "buildings": [],
            }
        ),
        encoding="utf-8",
    )


def resign(catalog: dict) -> None:
    catalog.pop("catalog_sha256", None)
    catalog["catalog_sha256"] = module.catalog_semantic_sha256(catalog)


def assert_rejects_path(catalog: dict, bad_path: str) -> None:
    original_path = next(iter(catalog["source_document_sha256"]))
    digest = catalog["source_document_sha256"].pop(original_path)
    catalog["source_document_sha256"][bad_path] = digest
    entry = catalog["entries"]["42"]
    entry["source_paths"] = [bad_path]
    entry["source_file_count"] = 1
    resign(catalog)

    try:
        module.validate_contract(catalog)
    except SystemExit as exc:
        assert "non-canonical source document path" in str(exc), str(exc)
    else:
        raise AssertionError(f"catalog accepted non-canonical source path: {bad_path!r}")


def test_catalog_source_paths_fail_closed() -> None:
    mutations = (
        "data/osm/../shadow.game.json",
        "data/osm/./slice.game.json",
        "data/osm/sub\\slice.game.json",
        "/data/osm/slice.game.json",
    )
    for bad_path in mutations:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "data" / "osm"
            write_document(root / "slice.game.json")
            catalog = module.build_catalog(root)
            module.validate_contract(catalog)
            assert_rejects_path(catalog, bad_path)


if __name__ == "__main__":
    test_catalog_source_paths_fail_closed()
    print("ROAD_DESTINATION_CATALOG_SOURCE_PATH_TEST_OK")
