import hashlib
import json
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "data/source_plans/brussels_spatial_crosswalk_origin_evidence.lock.json"
REPOSITORY_RECEIPT = ROOT / "data/source_plans/brussels_spatial_crosswalk_repository_content_receipt.lock.json"
REGISTERED_INDEX = ROOT / "data/provenance/brussels_registered_cell_manifest_index.json"
RUNTIME_INDEX = ROOT / "data/runtime/road_destination_runtime_index.json"

RECEIPT_KEYS = {
    "schema",
    "registered_cell_index",
    "road_runtime_index",
    "authorization",
    "scope_note",
}
REGISTERED_INDEX_RECEIPT_KEYS = {"path", "git_blob_sha1", "semantic_sha256"}
RUNTIME_INDEX_RECEIPT_KEYS = {"path", "git_blob_sha1", "catalog_sha256"}
AUTHORIZATION_KEYS = {
    "crosswalk_authorized",
    "road_cell_mapping_authorized",
    "runtime_mount_authorized",
    "rendered_geometry_authorized",
    "collision_authorized",
    "safe_spawn_authorized",
    "jouable_promotion_authorized",
}


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _git_blob_sha1(path: Path) -> str:
    raw = path.read_bytes()
    return hashlib.sha1(f"blob {len(raw)}\0".encode("ascii") + raw).hexdigest()


def _reject_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def _load_json_strict(path: Path):
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=_reject_duplicate_keys)


def _require_exact_keys(value: dict, expected: set[str], label: str) -> None:
    actual = set(value)
    assert actual == expected, (
        f"{label} keys drifted: missing={sorted(expected - actual)} "
        f"unexpected={sorted(actual - expected)}"
    )


def _validate_repository_receipt_schema(receipt: dict) -> None:
    _require_exact_keys(receipt, RECEIPT_KEYS, "repository receipt")
    _require_exact_keys(
        receipt["registered_cell_index"],
        REGISTERED_INDEX_RECEIPT_KEYS,
        "registered-cell receipt",
    )
    _require_exact_keys(
        receipt["road_runtime_index"],
        RUNTIME_INDEX_RECEIPT_KEYS,
        "road-runtime receipt",
    )
    _require_exact_keys(receipt["authorization"], AUTHORIZATION_KEYS, "receipt authorization")
    assert isinstance(receipt["scope_note"], str) and receipt["scope_note"].strip()


def test_repository_content_receipt_rejects_duplicate_json_keys(tmp_path: Path):
    duplicate = tmp_path / "duplicate.json"
    duplicate.write_text(
        '{"schema":"grand-bruxelles-spatial-crosswalk-repository-content-receipt-v1",'
        '"schema":"forged-schema"}',
        encoding="utf-8",
    )
    with pytest.raises(ValueError, match="duplicate JSON key: schema"):
        _load_json_strict(duplicate)


def test_repository_content_receipt_rejects_undeclared_fields():
    receipt = _load_json_strict(REPOSITORY_RECEIPT)
    receipt["authorization_override"] = True
    with pytest.raises(AssertionError, match="repository receipt keys drifted"):
        _validate_repository_receipt_schema(receipt)


def test_spatial_crosswalk_repository_content_receipt_locks_exact_repository_blobs():
    assert REPOSITORY_RECEIPT.is_file(), "immutable repository-content receipt is required"
    receipt = _load_json_strict(REPOSITORY_RECEIPT)
    evidence = _load_json_strict(EVIDENCE)
    measured = evidence["measured_contract"]

    _validate_repository_receipt_schema(receipt)
    assert receipt["schema"] == "grand-bruxelles-spatial-crosswalk-repository-content-receipt-v1"
    assert receipt["registered_cell_index"] == {
        "path": REGISTERED_INDEX.relative_to(ROOT).as_posix(),
        "git_blob_sha1": _git_blob_sha1(REGISTERED_INDEX),
        "semantic_sha256": measured["registered_cell_index_semantic_sha256"],
    }
    assert receipt["road_runtime_index"] == {
        "path": RUNTIME_INDEX.relative_to(ROOT).as_posix(),
        "git_blob_sha1": _git_blob_sha1(RUNTIME_INDEX),
        "catalog_sha256": measured["road_runtime_catalog_sha256"],
    }
    assert all(
        type(receipt["authorization"][key]) is bool and receipt["authorization"][key] is False
        for key in AUTHORIZATION_KEYS
    )


def test_spatial_crosswalk_evidence_is_bound_to_repository_content():
    evidence = _load_json_strict(EVIDENCE)
    measured = evidence["measured_contract"]
    registered_index = _load_json_strict(REGISTERED_INDEX)
    runtime_index = _load_json_strict(RUNTIME_INDEX)

    assert measured["registered_cell_index"] == REGISTERED_INDEX.relative_to(ROOT).as_posix()
    assert measured["road_runtime_index"] == RUNTIME_INDEX.relative_to(ROOT).as_posix()

    assert registered_index["semantic_sha256"] == measured["registered_cell_index_semantic_sha256"]
    assert registered_index["registered_cell_count"] == measured["registered_cell_count"]
    assert len(registered_index["entries"]) == measured["registered_cell_count"]

    for entry in registered_index["entries"]:
        manifest_path = ROOT / entry["manifest_path"]
        assert manifest_path.is_file(), f"missing registered cell manifest: {entry['manifest_path']}"
        assert _sha256(manifest_path) == entry["manifest_sha256"], (
            f"registered cell manifest drift: {entry['manifest_path']}"
        )
        assert entry["evidence_only"] is True
        for key in (
            "collision_authorized",
            "jouable_promotion_authorized",
            "rendered_geometry_authorized",
            "runtime_mount_authorized",
            "safe_spawn_authorized",
        ):
            assert entry[key] is False, f"unexpected authorization in {entry['cell_id']}: {key}"

    assert runtime_index["catalog_sha256"] == measured["road_runtime_catalog_sha256"]
    assert runtime_index["source_lookup_only"] is True
    assert runtime_index["authorization"]["source_lookup_only"] is True
    for key, value in runtime_index["authorization"].items():
        if key != "source_lookup_only":
            assert value is False, f"runtime index authorization opened unexpectedly: {key}"

    source_path = ROOT / measured["road_source"]
    assert source_path.is_file(), f"missing measured road source: {measured['road_source']}"
    assert _sha256(source_path) == measured["road_source_sha256"]

    matching_documents = [
        document
        for document in runtime_index["documents"]
        if document["path"] == measured["road_source"]
    ]
    assert len(matching_documents) == 1, "runtime index must bind exactly one measured road source document"
    assert matching_documents[0]["sha256"] == measured["road_source_sha256"]

    authorization = evidence["authorization"]
    assert authorization and all(type(value) is bool and value is False for value in authorization.values())
