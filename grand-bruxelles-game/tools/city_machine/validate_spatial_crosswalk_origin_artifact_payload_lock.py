from __future__ import annotations

import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
LOCK_PATH = ROOT / "data/source_plans/brussels_spatial_crosswalk_origin_artifact_payload.lock.json"
RECEIPT_PATH = ROOT / "data/source_plans/brussels_spatial_crosswalk_origin_artifact_receipt.lock.json"

EXPECTED_LOCK = {
    "schema": "grand-bruxelles-spatial-crosswalk-origin-artifact-payload-v1",
    "repository": "Chatnoir01/Chatnoir01",
    "workflow_run_id": 34248313500,
    "workflow_head_sha": "9fdbf01073deb311097bcc70e2e8b627a004a8b1",
    "artifact_id": 10065069360,
    "artifact_name": "road-registered-cell-overlap-v2-candidate",
    "archive_size_in_bytes": 2473,
    "archive_sha256": "7c6dbd4e1ce3feeca476d60acfb147f97dd4cd43a0bc1063ca2d12059a230894",
    "members": [{
        "name": "road_registered_cell_overlap_v2.json",
        "size_in_bytes": 19401,
        "sha256": "95310885fcf030530dddae5b85eacdec79b7f407d3e9f2f0934c2b1e1e7e2ee6",
    }],
    "authorization": {
        "crosswalk_authorized": False,
        "road_cell_mapping_authorized": False,
        "runtime_mount_authorized": False,
        "rendered_geometry_authorized": False,
        "collision_authorized": False,
        "safe_spawn_authorized": False,
        "jouable_promotion_authorized": False,
    },
    "scope_note": "Deterministic byte identity for the exact extracted payload of GitHub Actions artifact 10065069360, independently downloaded while unexpired. This lock records provenance only and grants no runtime, geometry, collision, spawn or JOUABLE authorization.",
}


def _reject_duplicate_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def _reject_non_standard_constant(value: str) -> None:
    raise ValueError(f"non-standard JSON constant: {value}")


def _load(raw: bytes, label: str) -> Any:
    try:
        return json.loads(
            raw.decode("utf-8"),
            object_pairs_hook=_reject_duplicate_pairs,
            parse_constant=_reject_non_standard_constant,
        )
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError(f"{label} is not strict UTF-8 JSON") from exc


def validate_payload_lock(lock_raw: bytes, receipt_raw: bytes) -> None:
    lock = _load(lock_raw, "origin artifact payload lock")
    receipt = _load(receipt_raw, "origin artifact receipt")
    if lock != EXPECTED_LOCK:
        raise ValueError("origin artifact payload lock immutable identity drift")
    run = receipt.get("workflow_run")
    artifact = receipt.get("artifact")
    if not isinstance(run, dict) or not isinstance(artifact, dict):
        raise ValueError("origin artifact receipt shape drift")
    if run.get("id") != lock["workflow_run_id"] or run.get("head_sha") != lock["workflow_head_sha"]:
        raise ValueError("origin artifact payload lock workflow identity mismatch")
    if artifact.get("id") != lock["artifact_id"] or artifact.get("name") != lock["artifact_name"]:
        raise ValueError("origin artifact payload lock artifact identity mismatch")
    if artifact.get("size_in_bytes") != lock["archive_size_in_bytes"]:
        raise ValueError("origin artifact payload lock archive size mismatch")
    if artifact.get("digest") != f"sha256:{lock['archive_sha256']}":
        raise ValueError("origin artifact payload lock archive digest mismatch")


def main() -> int:
    validate_payload_lock(LOCK_PATH.read_bytes(), RECEIPT_PATH.read_bytes())
    print("spatial crosswalk origin artifact payload lock: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
