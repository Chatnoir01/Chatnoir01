#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
VALIDATOR = PROJECT / "tools" / "validate_road_destination_source_lock.py"
CROSSWALK_VALIDATOR = PROJECT / "tools" / "validate_required_building_urbis_crosswalk_lock.py"
LOCK = PROJECT / "data" / "osm" / "road_destination_sources.lock.json"
SOURCE = PROJECT / "data" / "osm" / "vertical_slice_01.game.json"
SOURCE_KEY = "data/osm/vertical_slice_01.game.json"


def _run(lock_path: Path, source_path: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(VALIDATOR), "--source-root", str(source_path.parent), "--lock", str(lock_path)],
        cwd=PROJECT,
        capture_output=True,
        text=True,
        check=False,
    )


def _run_crosswalk(source_path: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(CROSSWALK_VALIDATOR), "--source", str(source_path)],
        cwd=PROJECT,
        capture_output=True,
        text=True,
        check=False,
    )


def _write_temp_case(
    tmp: str, lock_doc: dict[str, object], source_doc: dict[str, object]
) -> tuple[Path, Path]:
    source_root = Path(tmp) / "data" / "osm"
    source_root.mkdir(parents=True)
    source_path = source_root / "vertical_slice_01.game.json"
    lock_path = source_root / "road_destination_sources.lock.json"
    source_bytes = json.dumps(source_doc, separators=(",", ":"), ensure_ascii=False, allow_nan=False).encode("utf-8")
    source_path.write_bytes(source_bytes)
    effective_lock = json.loads(json.dumps(lock_doc))
    documents = effective_lock["documents"]
    assert isinstance(documents, dict)
    documents[SOURCE_KEY] = hashlib.sha256(source_bytes).hexdigest()
    lock_path.write_text(json.dumps(effective_lock, sort_keys=True, allow_nan=False), encoding="utf-8")
    return lock_path, source_path


def _expect_rejected(lock_doc: dict[str, object], source_doc: dict[str, object], needle: str) -> None:
    with tempfile.TemporaryDirectory(prefix="gb-required-building-") as tmp:
        lock_path, source_path = _write_temp_case(tmp, lock_doc, source_doc)
        result = _run(lock_path, source_path)
        assert result.returncode != 0, result.stdout + result.stderr
        assert needle.lower() in (result.stdout + result.stderr).lower(), result.stdout + result.stderr


def _expect_crosswalk_rejected(lock_doc: dict[str, object], source_doc: dict[str, object]) -> None:
    with tempfile.TemporaryDirectory(prefix="gb-bourse-crosswalk-") as tmp:
        lock_path, source_path = _write_temp_case(tmp, lock_doc, source_doc)

        digest_only = _run(lock_path, source_path)
        assert digest_only.returncode == 0, digest_only.stdout + digest_only.stderr

        crosswalk = _run_crosswalk(source_path)
        assert crosswalk.returncode != 0, crosswalk.stdout + crosswalk.stderr
        output = crosswalk.stdout + crosswalk.stderr
        assert "historical bourse urbis crosswalk drift" in output.lower(), output


def _first_required_building(source_doc: dict[str, object]) -> dict[str, object]:
    corridor = source_doc["corridor"]
    assert isinstance(corridor, dict)
    required = corridor["required_buildings"]
    assert isinstance(required, list) and required and isinstance(required[0], dict)
    return required[0]


def main() -> int:
    lock_doc = json.loads(LOCK.read_text(encoding="utf-8"))
    source_doc = json.loads(SOURCE.read_text(encoding="utf-8"))
    corridor = source_doc.get("corridor")
    assert isinstance(corridor, dict)
    required = corridor.get("required_buildings")
    assert isinstance(required, list) and required and isinstance(required[0], dict)

    canonical_crosswalk = _run_crosswalk(SOURCE)
    assert canonical_crosswalk.returncode == 0, canonical_crosswalk.stdout + canonical_crosswalk.stderr

    bad_required_type = json.loads(json.dumps(source_doc))
    bad_corridor = bad_required_type["corridor"]
    assert isinstance(bad_corridor, dict)
    bad_corridor["required_buildings"] = {}
    _expect_rejected(lock_doc, bad_required_type, "required_buildings")

    bad_osm_id = json.loads(json.dumps(source_doc))
    bad_corridor = bad_osm_id["corridor"]
    assert isinstance(bad_corridor, dict)
    bad_required = bad_corridor["required_buildings"]
    assert isinstance(bad_required, list) and isinstance(bad_required[0], dict)
    bad_required[0]["osm_id"] = str(bad_required[0]["osm_id"])
    _expect_rejected(lock_doc, bad_osm_id, "osm_id")

    bad_source_license = json.loads(json.dumps(source_doc))
    bad_corridor = bad_source_license["corridor"]
    assert isinstance(bad_corridor, dict)
    bad_required = bad_corridor["required_buildings"]
    assert isinstance(bad_required, list) and isinstance(bad_required[0], dict)
    bad_required[0]["source_license"] = "UNKNOWN"
    _expect_rejected(lock_doc, bad_source_license, "source_license")

    bad_urbis_crs = json.loads(json.dumps(source_doc))
    bad_corridor = bad_urbis_crs["corridor"]
    assert isinstance(bad_corridor, dict)
    bad_required = bad_corridor["required_buildings"]
    assert isinstance(bad_required, list) and isinstance(bad_required[0], dict)
    bad_required[0]["urbis_crs"] = "EPSG:4326"
    _expect_rejected(lock_doc, bad_urbis_crs, "urbis_crs")

    bourse = required[0]
    assert bourse["osm_type"] == "way"
    assert bourse["osm_id"] == 13494623
    assert bourse["urbis_inspire_id"] == "https://databrussels.be/id/building/1751663"
    assert bourse["urbis_ref"] == "8186511"
    assert bourse["urbis_crs"] == "EPSG:31370"
    assert bourse["urbis_area_m2"] == 3368
    assert bourse["cross_check_accessed_at"] == "2026-08-12"

    crosswalk_mutations = (
        ("urbis_inspire_id", "https://databrussels.be/id/building/1751664"),
        ("urbis_ref", "8186512"),
        ("urbis_area_m2", 3369),
        ("cross_check_accessed_at", "2026-08-13"),
    )
    for field, replacement in crosswalk_mutations:
        drifted = json.loads(json.dumps(source_doc))
        _first_required_building(drifted)[field] = replacement
        _expect_crosswalk_rejected(lock_doc, drifted)

    bad_runtime_approval = json.loads(json.dumps(source_doc))
    bad_corridor = bad_runtime_approval["corridor"]
    assert isinstance(bad_corridor, dict)
    bad_required = bad_corridor["required_buildings"]
    assert isinstance(bad_required, list) and isinstance(bad_required[0], dict)
    approval = bad_required[0]["runtime_approval"]
    assert isinstance(approval, dict)
    approval["frontage"] = True
    _expect_rejected(lock_doc, bad_runtime_approval, "runtime_approval")

    print("REQUIRED_BUILDING_PROVENANCE_LOCK_TEST_OK network_used=false")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
