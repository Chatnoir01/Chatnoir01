from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE_PATH = ROOT / "data/source_plans/brussels_spatial_crosswalk_origin_evidence.lock.json"
RECEIPT_PATH = ROOT / "data/source_plans/brussels_spatial_crosswalk_origin_artifact_receipt.lock.json"

EXPECTED_EVIDENCE_SCHEMA = "grand-bruxelles-spatial-crosswalk-origin-evidence-v1"
EXPECTED_RECEIPT_SCHEMA = "grand-bruxelles-spatial-crosswalk-origin-artifact-receipt-v1"
EXPECTED_REPOSITORY = "Chatnoir01/Chatnoir01"
EXPECTED_OWNER = {
    "pr": 1562,
    "head_sha": "9fdbf01073deb311097bcc70e2e8b627a004a8b1",
    "workflow": "Grand Bruxelles City Machine Midi Runtime-Index Frame",
    "run_id": 34248313500,
    "artifact_id": 10065069360,
    "artifact_digest": "sha256:7c6dbd4e1ce3feeca476d60acfb147f97dd4cd43a0bc1063ca2d12059a230894",
    "artifact_name": "road-registered-cell-overlap-v2-candidate",
}
EXPECTED_ARTIFACT_SIZE = 2473
EXPECTED_EVIDENCE_SCOPE_NOTE = "Pinned measured origin/CRS/grid evidence from #1562 for Data provenance intake only. This receipt does not identify municipality road artifacts, authorize OSM-to-UrbIS semantics, assign cells, mount runtime geometry, or promote JOUABLE."
EXPECTED_RECEIPT_SCOPE_NOTE = "Immutable receipt of the exact #1562 workflow artifact metadata independently re-verified through GitHub Actions. This receipt proves artifact identity only; it does not authorize source semantics, cell assignment, runtime mounting, collision, spawn safety or JOUABLE promotion."
EXPECTED_EVIDENCE_KEYS = {"schema", "source_owner", "measured_contract", "authorization", "scope_note"}
EXPECTED_OWNER_KEYS = {"pr", "head_sha", "workflow", "run_id", "artifact_id", "artifact_digest", "artifact_name"}
EXPECTED_RECEIPT_KEYS = {"schema", "repository", "workflow_run", "artifact", "authorization", "scope_note"}
EXPECTED_RUN_KEYS = {"id", "head_sha"}
EXPECTED_ARTIFACT_KEYS = {"id", "name", "size_in_bytes", "digest"}
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
SHA256_DIGEST = re.compile(r"^sha256:[0-9a-f]{64}$")


def _reject_duplicate_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    payload: dict[str, Any] = {}
    for key, value in pairs:
        if key in payload:
            raise ValueError(f"duplicate JSON key: {key}")
        payload[key] = value
    return payload


def _load_json_strict(raw: bytes, label: str) -> Any:
    try:
        return json.loads(raw.decode("utf-8"), object_pairs_hook=_reject_duplicate_pairs)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError(f"{label} is not valid UTF-8 JSON") from exc


def _require_exact_keys(value: Any, expected: set[str], label: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != expected:
        raise ValueError(f"{label} schema drift")
    return value


def _require_closed_authorization(value: Any, label: str) -> None:
    authorization = _require_exact_keys(value, EXPECTED_AUTHORIZATION_KEYS, label)
    for key, state in authorization.items():
        if type(state) is not bool or state is not False:
            raise ValueError(f"{label}.{key} must remain false")


def _require_scope_note(value: Any, expected: str, label: str) -> None:
    if not isinstance(value, str) or value != expected:
        raise ValueError(f"{label} immutable semantics drift")


def validate_origin_artifact_receipt(evidence_raw: bytes, receipt_raw: bytes) -> None:
    evidence = _load_json_strict(evidence_raw, "origin evidence")
    receipt = _load_json_strict(receipt_raw, "origin artifact receipt")

    evidence = _require_exact_keys(evidence, EXPECTED_EVIDENCE_KEYS, "origin evidence")
    receipt = _require_exact_keys(receipt, EXPECTED_RECEIPT_KEYS, "origin artifact receipt")

    if evidence["schema"] != EXPECTED_EVIDENCE_SCHEMA:
        raise ValueError("origin evidence schema drift")
    if receipt["schema"] != EXPECTED_RECEIPT_SCHEMA:
        raise ValueError("origin artifact receipt schema drift")
    if receipt["repository"] != EXPECTED_REPOSITORY:
        raise ValueError("origin artifact receipt repository drift")

    owner = _require_exact_keys(evidence["source_owner"], EXPECTED_OWNER_KEYS, "origin evidence source_owner")
    if owner != EXPECTED_OWNER:
        raise ValueError("origin evidence source_owner immutable identity drift")
    if LOWER_HEX_40.fullmatch(owner["head_sha"]) is None:
        raise ValueError("origin evidence source_owner.head_sha must be lowercase Git SHA-1")
    if SHA256_DIGEST.fullmatch(owner["artifact_digest"]) is None:
        raise ValueError("origin evidence source_owner.artifact_digest must be sha256:<lowerhex64>")

    run = _require_exact_keys(receipt["workflow_run"], EXPECTED_RUN_KEYS, "origin artifact receipt workflow_run")
    artifact = _require_exact_keys(receipt["artifact"], EXPECTED_ARTIFACT_KEYS, "origin artifact receipt artifact")

    expected_run = {"id": EXPECTED_OWNER["run_id"], "head_sha": EXPECTED_OWNER["head_sha"]}
    expected_artifact = {
        "id": EXPECTED_OWNER["artifact_id"],
        "name": EXPECTED_OWNER["artifact_name"],
        "size_in_bytes": EXPECTED_ARTIFACT_SIZE,
        "digest": EXPECTED_OWNER["artifact_digest"],
    }
    if run != expected_run or artifact != expected_artifact:
        raise ValueError("origin artifact receipt does not match source_owner")

    _require_closed_authorization(evidence["authorization"], "origin evidence authorization")
    _require_closed_authorization(receipt["authorization"], "origin artifact receipt authorization")
    _require_scope_note(evidence["scope_note"], EXPECTED_EVIDENCE_SCOPE_NOTE, "origin evidence scope_note")
    _require_scope_note(receipt["scope_note"], EXPECTED_RECEIPT_SCOPE_NOTE, "origin artifact receipt scope_note")


def main() -> int:
    validate_origin_artifact_receipt(EVIDENCE_PATH.read_bytes(), RECEIPT_PATH.read_bytes())
    print("spatial crosswalk origin artifact receipt: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
