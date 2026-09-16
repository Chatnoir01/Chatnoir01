#!/usr/bin/env python3
"""Exercise synthetic source structure in core; keep source-lock ambiguity canonical."""
from __future__ import annotations

import hashlib
import importlib.util
import tempfile
from pathlib import Path

CASES_PATH = Path(__file__).resolve().with_name("_road_destination_catalog_source_structure_cases.py")
spec = importlib.util.spec_from_file_location("road_destination_catalog_source_structure_cases", CASES_PATH)
assert spec and spec.loader
cases = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cases)

TOOLS_DIR = Path(__file__).resolve().parents[1]
CORE_PATH = TOOLS_DIR / "_road_destination_catalog_core.py"
CORE_SPEC = importlib.util.spec_from_file_location("road_destination_catalog_source_structure_core", CORE_PATH)
assert CORE_SPEC and CORE_SPEC.loader
core = importlib.util.module_from_spec(CORE_SPEC)
CORE_SPEC.loader.exec_module(core)

# The cases below intentionally model only canonical OSM document structure. They
# must not fabricate provenance/evidence/source-lock metadata merely to reach the
# mature structural validator. Production source selection remains lock-bound.
canonical_module = cases.module
cases.module = core


def reject_duplicate_lock_keys() -> None:
    """A textual production lock with duplicate object keys is ambiguous and must fail closed."""
    with tempfile.TemporaryDirectory() as tmp:
        source_root = Path(tmp) / "data" / "osm"
        source_root.mkdir(parents=True, exist_ok=True)
        source_path = source_root / "duplicate-key.game.json"
        cases.write_json(source_path, {
            "format": "grand-bruxelles-osm-v1",
            "roads": [cases.valid_road()],
            "buildings": [],
        })
        digest = hashlib.sha256(source_path.read_bytes()).hexdigest()
        relative = "data/osm/duplicate-key.game.json"
        lock_text = (
            "{"
            "\"format\":\"grand-bruxelles-road-destination-source-lock-v1\","
            "\"source_format\":\"grand-bruxelles-osm-v1\","
            "\"source\":\"OpenStreetMap contributors via Overpass API\","
            "\"license\":\"ODbL-1.0\","
            "\"evidence_artifact_id\":9733298021,"
            "\"evidence_catalog_sha256\":\"786c9cbf3b420a658066bcdc809343abb463bd242b4aef432ab2c7975fa1baef\","
            f"\"documents\":{{\"{relative}\":\"{digest}\"}},"
            f"\"documents\":{{\"{relative}\":\"{digest}\"}}"
            "}"
        )
        (source_root / "road_destination_sources.lock.json").write_text(lock_text, encoding="utf-8")
        try:
            canonical_module.build_catalog(source_root)
        except SystemExit as exc:
            assert "duplicate JSON object key" in str(exc), str(exc)
        else:
            raise AssertionError("expected duplicate JSON object key in source lock to fail closed")


if __name__ == "__main__":
    reject_duplicate_lock_keys()
    raise SystemExit(cases.main())
