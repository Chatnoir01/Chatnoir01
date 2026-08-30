#!/usr/bin/env python3
"""Run JSON-contract regressions with an explicit lock for every source mutation."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import tempfile
from pathlib import Path

CASES_PATH = Path(__file__).resolve().with_name("_road_destination_catalog_json_contract_cases.py")
spec = importlib.util.spec_from_file_location("road_destination_catalog_json_contract_cases", CASES_PATH)
assert spec and spec.loader
cases = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cases)

_original_write_document = cases.write_document


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


def write_document_with_lock(path: Path, **kwargs: object) -> None:
    _original_write_document(path, **kwargs)
    source_root = next(
        parent for parent in path.parents
        if parent.name == "osm" and parent.parent.name == "data"
    )
    _refresh_lock(source_root)


cases.write_document = write_document_with_lock


def _run_duplicate_source_key_probe() -> None:
    """Canonical source JSON must reject duplicate object keys before derivation."""
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp) / "data" / "osm"
        root.mkdir(parents=True, exist_ok=True)
        source = root / "duplicate-key.game.json"
        source.write_text(
            '{"format":"grand-bruxelles-osm-v1","format":"grand-bruxelles-osm-v1",'
            '"roads":[{"osm_id":42,"name":"Rue Test","class":"tertiary",'
            '"width":7.0,"drivable":true,"points":[[0.0,0.0],[10.0,0.0]]}],'
            '"buildings":[]}',
            encoding="utf-8",
        )
        _refresh_lock(root)
        try:
            cases.module.build_catalog(root)
        except SystemExit as exc:
            assert "duplicate JSON object key" in str(exc), str(exc)
        else:
            raise AssertionError("expected duplicate source JSON object key to fail closed")


if __name__ == "__main__":
    result = cases.main()
    _run_duplicate_source_key_probe()
    raise SystemExit(result)
