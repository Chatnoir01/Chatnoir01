#!/usr/bin/env python3
"""Run source-structure regressions with a lock refreshed for each synthetic mutation."""
from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path

CASES_PATH = Path(__file__).resolve().with_name("_road_destination_catalog_source_structure_cases.py")
spec = importlib.util.spec_from_file_location("road_destination_catalog_source_structure_cases", CASES_PATH)
assert spec and spec.loader
cases = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cases)

_original_write_json = cases.write_json


def _refresh_lock(source_root: Path) -> None:
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


def write_json_with_lock(path: Path, payload: object) -> None:
    _original_write_json(path, payload)
    if path.name.endswith(".game.json"):
        source_root = next(
            parent for parent in path.parents
            if parent.name == "osm" and parent.parent.name == "data"
        )
        _refresh_lock(source_root)


cases.write_json = write_json_with_lock

if __name__ == "__main__":
    raise SystemExit(cases.main())
