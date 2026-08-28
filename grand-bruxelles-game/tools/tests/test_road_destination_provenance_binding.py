#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "build_road_destination_provenance_binding.py"
WORKFLOW = ROOT.parent / ".github" / "workflows" / "grand-bruxelles-road-destination-provenance-binding.yml"
spec = importlib.util.spec_from_file_location("road_provenance_binding", SCRIPT)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def test_real_binding_is_deterministic_and_fail_closed() -> None:
    source_root = ROOT / "data" / "osm"
    readiness = ROOT / "data" / "provenance" / "brussels_road_destination_readiness_catalog.json"
    catalog_builder = ROOT / "tools" / "build_road_destination_catalog.py"
    first = module.build_binding(source_root, readiness, catalog_builder)
    second = module.build_binding(source_root, readiness, catalog_builder)
    module.validate_binding(first)
    module.validate_binding(second)
    assert module.canonical_json(first) == module.canonical_json(second)
    assert first["registered_not_rendered_count"] == 96
    assert first["mapped_cell_count"] == 4
    assert first["entry_count"] >= first["registered_not_rendered_count"]
    assert first["discovered_only_count"] == first["entry_count"] - 96
    assert first["municipality_niscodes"]
    for row in first["entries"].values():
        assert row["state"] in {"DISCOVERED", "REGISTERED_NOT_RENDERED"}
        for key in ("render_authorized", "collision_authorized", "runtime_mount_authorized", "safe_spawn_authorized", "jouable_authorized"):
            assert row[key] is False
        if row["state"] == "REGISTERED_NOT_RENDERED":
            assert row["cell_crs"] == "EPSG:31370"
            assert row["cell_id"].startswith("bxl-")
            assert row["municipalities"]
            assert abs(sum(float(m["coverage_ratio"]) for m in row["municipalities"]) - 1.0) < 1e-9


def test_tampered_readiness_semantic_fails_closed() -> None:
    source_root = ROOT / "data" / "osm"
    readiness_path = ROOT / "data" / "provenance" / "brussels_road_destination_readiness_catalog.json"
    catalog_builder = ROOT / "tools" / "build_road_destination_catalog.py"
    with tempfile.TemporaryDirectory() as tmp:
        tampered_path = Path(tmp) / "readiness.json"
        tampered = json.loads(readiness_path.read_text(encoding="utf-8"))
        tampered["destinations"][0]["cell_id"] = "bxl-tampered"
        tampered_path.write_text(json.dumps(tampered), encoding="utf-8")
        try:
            module.build_binding(source_root, tampered_path, catalog_builder)
        except SystemExit as exc:
            assert "readiness semantic drift" in str(exc)
        else:
            raise AssertionError("tampered readiness semantic evidence did not fail closed")


def test_opened_destination_authorization_fails_closed_even_with_rehashed_readiness() -> None:
    source_root = ROOT / "data" / "osm"
    readiness_path = ROOT / "data" / "provenance" / "brussels_road_destination_readiness_catalog.json"
    catalog_builder = ROOT / "tools" / "build_road_destination_catalog.py"
    with tempfile.TemporaryDirectory() as tmp:
        changed_path = Path(tmp) / "readiness.json"
        changed = json.loads(readiness_path.read_text(encoding="utf-8"))
        changed["destinations"][0]["render_authorized"] = True
        unsigned = dict(changed)
        unsigned.pop("semantic_sha256", None)
        changed["semantic_sha256"] = module.sha256_json(unsigned)
        changed_path.write_text(json.dumps(changed), encoding="utf-8")
        try:
            module.build_binding(source_root, changed_path, catalog_builder)
        except SystemExit as exc:
            assert "opened render_authorized" in str(exc)
        else:
            raise AssertionError("opened render authorization did not fail closed")


def test_cell_manifest_byte_drift_fails_closed() -> None:
    readiness_path = ROOT / "data" / "provenance" / "brussels_road_destination_readiness_catalog.json"
    readiness = json.loads(readiness_path.read_text(encoding="utf-8"))
    destination = dict(readiness["destinations"][0])
    source_manifest = ROOT / destination["cell_manifest_path"]
    with tempfile.TemporaryDirectory() as tmp:
        project_root = Path(tmp)
        relative = Path(destination["cell_manifest_path"])
        copied = project_root / relative
        copied.parent.mkdir(parents=True, exist_ok=True)
        copied.write_bytes(source_manifest.read_bytes() + b"\n")
        try:
            module.verify_cell_manifest(project_root, destination, int(destination["road_osm_id"]))
        except SystemExit as exc:
            assert "cell manifest sha drift" in str(exc)
        else:
            raise AssertionError("tampered cell manifest bytes did not fail closed")


def test_workflow_publishes_only_verified_complete_evidence() -> None:
    workflow = WORKFLOW.read_text(encoding="utf-8")
    assert "- name: Verify provenance binding evidence before upload" in workflow
    verify = workflow.split("- name: Verify provenance binding evidence before upload", 1)[1]
    upload = verify.split("- name: Upload provenance binding evidence", 1)[1]
    assert 'test "$(wc -l < binding-file.sha256)" -eq 1' in verify
    assert "sha256sum --check binding-file.sha256" in verify
    assert "test -s binding-a.json" in verify
    assert "if: success()" in upload
    assert "if: always()" not in upload
    assert "if-no-files-found: error" in upload


def main() -> int:
    test_real_binding_is_deterministic_and_fail_closed()
    test_tampered_readiness_semantic_fails_closed()
    test_opened_destination_authorization_fails_closed_even_with_rehashed_readiness()
    test_cell_manifest_byte_drift_fails_closed()
    test_workflow_publishes_only_verified_complete_evidence()
    print("ROAD_PROVENANCE_BINDING_TEST_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())