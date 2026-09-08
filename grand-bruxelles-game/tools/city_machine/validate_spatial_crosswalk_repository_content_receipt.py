from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path, PurePosixPath
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
RECEIPT_PATH = "data/source_plans/brussels_spatial_crosswalk_repository_content_receipt.lock.json"
EXPECTED_SCHEMA = "grand-bruxelles-spatial-crosswalk-repository-content-receipt-v1"
EXPECTED_REGISTERED_PATH = "data/provenance/brussels_registered_cell_manifest_index.json"
EXPECTED_RUNTIME_PATH = "data/runtime/road_destination_runtime_index.json"
EXPECTED_TOP_LEVEL_KEYS = {
    "schema",
    "registered_cell_index",
    "road_runtime_index",
    "authorization",
    "scope_note",
}
EXPECTED_REGISTERED_KEYS = {"path", "git_blob_sha1", "semantic_sha256"}
EXPECTED_RUNTIME_KEYS = {"path", "git_blob_sha1", "catalog_sha256"}
EXPECTED_AUTHORIZATION_KEYS = {
    "crosswalk_authorized",
    "road_cell_mapping_authorized",
    "runtime_mount_authorized",
    "rendered_geometry_authorized",
    "collision_authorized",
    "safe_spawn_authorized",
    "jouable_promotion_authorized",
}
LOWER_HEX_40 = re.compile(r"^[0-9a-f]{40}$")
LOWER_HEX_64 = re.compile(r"^[0-9a-f]{64}$")


def _git_blob_sha1(raw: bytes) -> str:
    return hashlib.sha1(f"blob {len(raw)}\0".encode("ascii") + raw).hexdigest()


def _reject_duplicate_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def _load_json_strict(raw: bytes, label: str) -> Any:
    try:
        return json.loads(raw.decode("utf-8"), object_pairs_hook=_reject_duplicate_pairs)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError(f"{label} is not valid UTF-8 JSON") from exc


def _require_exact_keys(value: Any, expected: set[str], label: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != expected:
        raise ValueError(f"{label} schema drift")
    return value


def _require_lower_hex(value: Any, pattern: re.Pattern[str], label: str) -> str:
    if not isinstance(value, str) or pattern.fullmatch(value) is None:
        raise ValueError(f"{label} must be lowercase hexadecimal")
    return value


def _require_exact_repo_path(value: Any, expected: str, label: str) -> str:
    if value != expected:
        raise ValueError(f"{label} must equal canonical repository path")
    return expected


def _resolve_repo_path(repo_root: Path, value: Any, label: str) -> Path:
    if not isinstance(value, str) or not value or value != value.strip():
        raise ValueError(f"{label} must be a non-empty trimmed repository path")
    posix = PurePosixPath(value)
    if posix.is_absolute() or "." in posix.parts or ".." in posix.parts:
        raise ValueError(f"{label} must be repository-relative and canonical")
    resolved = (repo_root / Path(*posix.parts)).resolve()
    try:
        resolved.relative_to(repo_root.resolve())
    except ValueError as exc:
        raise ValueError(f"{label} escapes repository root") from exc
    return resolved


def validate_repository_content_receipt(receipt_raw: bytes, *, repo_root: Path = ROOT) -> None:
    receipt = _load_json_strict(receipt_raw, "repository-content receipt")
    _require_exact_keys(receipt, EXPECTED_TOP_LEVEL_KEYS, "repository-content receipt")
    if receipt["schema"] != EXPECTED_SCHEMA:
        raise ValueError("repository-content receipt schema mismatch")
    if not isinstance(receipt["scope_note"], str) or not receipt["scope_note"].strip():
        raise ValueError("repository-content receipt scope_note must be non-empty")

    registered = _require_exact_keys(
        receipt["registered_cell_index"], EXPECTED_REGISTERED_KEYS, "registered-cell receipt"
    )
    runtime = _require_exact_keys(
        receipt["road_runtime_index"], EXPECTED_RUNTIME_KEYS, "road-runtime receipt"
    )
    authorization = _require_exact_keys(
        receipt["authorization"], EXPECTED_AUTHORIZATION_KEYS, "repository-content authorization"
    )
    for key in EXPECTED_AUTHORIZATION_KEYS:
        if type(authorization[key]) is not bool or authorization[key] is not False:
            raise ValueError(f"repository-content authorization {key} must remain false")

    _require_exact_repo_path(registered["path"], EXPECTED_REGISTERED_PATH, "registered_cell_index.path")
    _require_exact_repo_path(runtime["path"], EXPECTED_RUNTIME_PATH, "road_runtime_index.path")
    registered_path = _resolve_repo_path(repo_root, registered["path"], "registered_cell_index.path")
    runtime_path = _resolve_repo_path(repo_root, runtime["path"], "road_runtime_index.path")
    for path, label in ((registered_path, "registered-cell index"), (runtime_path, "road-runtime index")):
        if not path.is_file():
            raise ValueError(f"{label} path does not exist")

    registered_blob = _require_lower_hex(
        registered["git_blob_sha1"], LOWER_HEX_40, "registered_cell_index.git_blob_sha1"
    )
    runtime_blob = _require_lower_hex(
        runtime["git_blob_sha1"], LOWER_HEX_40, "road_runtime_index.git_blob_sha1"
    )
    registered_semantic = _require_lower_hex(
        registered["semantic_sha256"], LOWER_HEX_64, "registered_cell_index.semantic_sha256"
    )
    runtime_catalog = _require_lower_hex(
        runtime["catalog_sha256"], LOWER_HEX_64, "road_runtime_index.catalog_sha256"
    )

    registered_raw = registered_path.read_bytes()
    runtime_raw = runtime_path.read_bytes()
    if _git_blob_sha1(registered_raw) != registered_blob:
        raise ValueError("registered-cell index Git blob mismatch")
    if _git_blob_sha1(runtime_raw) != runtime_blob:
        raise ValueError("road-runtime index Git blob mismatch")

    registered_payload = _load_json_strict(registered_raw, "registered-cell index")
    runtime_payload = _load_json_strict(runtime_raw, "road-runtime index")
    if not isinstance(registered_payload, dict) or registered_payload.get("semantic_sha256") != registered_semantic:
        raise ValueError("registered-cell semantic SHA-256 mismatch")
    if not isinstance(runtime_payload, dict) or runtime_payload.get("catalog_sha256") != runtime_catalog:
        raise ValueError("road-runtime catalog SHA-256 mismatch")


def main() -> int:
    receipt = ROOT / RECEIPT_PATH
    if not receipt.is_file():
        raise ValueError("immutable repository-content receipt is required")
    validate_repository_content_receipt(receipt.read_bytes(), repo_root=ROOT)
    print("spatial crosswalk repository-content receipt: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
