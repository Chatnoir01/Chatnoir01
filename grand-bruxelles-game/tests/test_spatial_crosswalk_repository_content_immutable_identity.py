from __future__ import annotations

import json
from pathlib import Path

import pytest

from tools.city_machine import validate_spatial_crosswalk_repository_content_receipt as validator

ROOT = Path(__file__).resolve().parents[1]
RECEIPT = ROOT / "data/source_plans/brussels_spatial_crosswalk_repository_content_receipt.lock.json"
CANONICAL_REGISTERED = ROOT / "data/provenance/brussels_registered_cell_manifest_index.json"
CANONICAL_RUNTIME = ROOT / "data/runtime/road_destination_runtime_index.json"


def _candidate_repo(tmp_path: Path) -> tuple[Path, Path, dict]:
    registered = tmp_path / "data/provenance/brussels_registered_cell_manifest_index.json"
    runtime = tmp_path / "data/runtime/road_destination_runtime_index.json"
    registered.parent.mkdir(parents=True)
    runtime.parent.mkdir(parents=True)
    receipt = json.loads(RECEIPT.read_text(encoding="utf-8"))
    return registered, runtime, receipt


def test_repinned_registered_producer_identity_drift_is_rejected(tmp_path: Path) -> None:
    registered, runtime, receipt = _candidate_repo(tmp_path)
    registered.write_text('{"semantic_sha256":"' + "a" * 64 + '"}\n', encoding="utf-8")
    runtime.write_bytes(CANONICAL_RUNTIME.read_bytes())
    receipt["registered_cell_index"]["git_blob_sha1"] = validator._git_blob_sha1(registered.read_bytes())
    receipt["registered_cell_index"]["semantic_sha256"] = "a" * 64

    with pytest.raises(ValueError, match="registered-cell immutable producer identity mismatch"):
        validator.validate_repository_content_receipt(
            (json.dumps(receipt, separators=(",", ":")) + "\n").encode("utf-8"), repo_root=tmp_path
        )


def test_repinned_runtime_producer_identity_drift_is_rejected(tmp_path: Path) -> None:
    registered, runtime, receipt = _candidate_repo(tmp_path)
    registered.write_bytes(CANONICAL_REGISTERED.read_bytes())
    runtime.write_text('{"catalog_sha256":"' + "b" * 64 + '"}\n', encoding="utf-8")
    receipt["road_runtime_index"]["git_blob_sha1"] = validator._git_blob_sha1(runtime.read_bytes())
    receipt["road_runtime_index"]["catalog_sha256"] = "b" * 64

    with pytest.raises(ValueError, match="road-runtime immutable producer identity mismatch"):
        validator.validate_repository_content_receipt(
            (json.dumps(receipt, separators=(",", ":")) + "\n").encode("utf-8"), repo_root=tmp_path
        )
