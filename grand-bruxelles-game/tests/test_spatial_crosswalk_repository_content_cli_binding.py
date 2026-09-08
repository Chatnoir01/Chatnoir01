from __future__ import annotations

import json
from pathlib import Path

import pytest

from tools.city_machine import validate_spatial_crosswalk_repository_content_receipt as validator

ROOT = Path(__file__).resolve().parents[1]
RECEIPT = ROOT / "data/source_plans/brussels_spatial_crosswalk_repository_content_receipt.lock.json"


def test_production_cli_validator_exposes_repository_content_binding() -> None:
    assert callable(validator.validate_repository_content_receipt)


def test_repository_content_binding_rejects_repinned_repository_byte_drift(tmp_path: Path) -> None:
    repo_root = tmp_path
    registered = repo_root / "data/provenance/brussels_registered_cell_manifest_index.json"
    runtime = repo_root / "data/runtime/road_destination_runtime_index.json"
    registered.parent.mkdir(parents=True)
    runtime.parent.mkdir(parents=True)
    registered.write_text('{"semantic_sha256":"' + "a" * 64 + '"}\n', encoding="utf-8")
    runtime.write_text('{"catalog_sha256":"' + "b" * 64 + '"}\n', encoding="utf-8")

    receipt = json.loads(RECEIPT.read_text(encoding="utf-8"))
    receipt["registered_cell_index"]["semantic_sha256"] = "a" * 64
    receipt["road_runtime_index"]["catalog_sha256"] = "b" * 64
    receipt["registered_cell_index"]["git_blob_sha1"] = validator._git_blob_sha1(registered.read_bytes())
    receipt["road_runtime_index"]["git_blob_sha1"] = validator._git_blob_sha1(runtime.read_bytes())
    candidate_raw = (json.dumps(receipt, separators=(",", ":")) + "\n").encode("utf-8")

    validator.validate_repository_content_receipt(candidate_raw, repo_root=repo_root)

    registered.write_text('{"semantic_sha256":"' + "c" * 64 + '"}\n', encoding="utf-8")
    with pytest.raises(ValueError, match="registered-cell index Git blob mismatch"):
        validator.validate_repository_content_receipt(candidate_raw, repo_root=repo_root)


def test_repository_content_binding_rejects_registered_role_path_substitution(tmp_path: Path) -> None:
    repo_root = tmp_path
    forged_registered = repo_root / "data/provenance/forged_registered_index.json"
    runtime = repo_root / "data/runtime/road_destination_runtime_index.json"
    forged_registered.parent.mkdir(parents=True)
    runtime.parent.mkdir(parents=True)
    forged_registered.write_text('{"semantic_sha256":"' + "a" * 64 + '"}\n', encoding="utf-8")
    runtime.write_text('{"catalog_sha256":"' + "b" * 64 + '"}\n', encoding="utf-8")

    receipt = json.loads(RECEIPT.read_text(encoding="utf-8"))
    receipt["registered_cell_index"]["path"] = "data/provenance/forged_registered_index.json"
    receipt["registered_cell_index"]["semantic_sha256"] = "a" * 64
    receipt["registered_cell_index"]["git_blob_sha1"] = validator._git_blob_sha1(forged_registered.read_bytes())
    receipt["road_runtime_index"]["catalog_sha256"] = "b" * 64
    receipt["road_runtime_index"]["git_blob_sha1"] = validator._git_blob_sha1(runtime.read_bytes())

    with pytest.raises(ValueError, match="registered_cell_index.path must equal canonical repository path"):
        validator.validate_repository_content_receipt(
            (json.dumps(receipt, separators=(",", ":")) + "\n").encode("utf-8"),
            repo_root=repo_root,
        )


def test_repository_content_binding_rejects_runtime_role_path_substitution(tmp_path: Path) -> None:
    repo_root = tmp_path
    registered = repo_root / "data/provenance/brussels_registered_cell_manifest_index.json"
    forged_runtime = repo_root / "data/runtime/forged_runtime_index.json"
    registered.parent.mkdir(parents=True)
    forged_runtime.parent.mkdir(parents=True)
    registered.write_text('{"semantic_sha256":"' + "a" * 64 + '"}\n', encoding="utf-8")
    forged_runtime.write_text('{"catalog_sha256":"' + "b" * 64 + '"}\n', encoding="utf-8")

    receipt = json.loads(RECEIPT.read_text(encoding="utf-8"))
    receipt["registered_cell_index"]["semantic_sha256"] = "a" * 64
    receipt["registered_cell_index"]["git_blob_sha1"] = validator._git_blob_sha1(registered.read_bytes())
    receipt["road_runtime_index"]["path"] = "data/runtime/forged_runtime_index.json"
    receipt["road_runtime_index"]["catalog_sha256"] = "b" * 64
    receipt["road_runtime_index"]["git_blob_sha1"] = validator._git_blob_sha1(forged_runtime.read_bytes())

    with pytest.raises(ValueError, match="road_runtime_index.path must equal canonical repository path"):
        validator.validate_repository_content_receipt(
            (json.dumps(receipt, separators=(",", ":")) + "\n").encode("utf-8"),
            repo_root=repo_root,
        )


def test_repository_content_binding_rejects_duplicate_keys_and_open_authorization() -> None:
    raw = RECEIPT.read_bytes()
    duplicate = raw.replace(
        b'"schema": "grand-bruxelles-spatial-crosswalk-repository-content-receipt-v1",',
        b'"schema": "grand-bruxelles-spatial-crosswalk-repository-content-receipt-v1",\n  "schema": "forged",',
        1,
    )
    with pytest.raises(ValueError, match="duplicate JSON key: schema"):
        validator.validate_repository_content_receipt(duplicate, repo_root=ROOT)

    receipt = json.loads(raw.decode("utf-8"))
    receipt["authorization"]["runtime_mount_authorized"] = True
    with pytest.raises(ValueError, match="runtime_mount_authorized must remain false"):
        validator.validate_repository_content_receipt(
            (json.dumps(receipt, separators=(",", ":")) + "\n").encode("utf-8"),
            repo_root=ROOT,
        )
