#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from typing import Any

PIN_SCHEMA = "grand-bruxelles-locked-evidence-git-blob-pin-v1"
PIN_KEYS = {"schema", "target_path", "git_blob_sha1"}
EXPECTED_TARGET_PATH = "data/source_plans/brussels_missing_road_source_acquisition_evidence.lock.json"
EXPECTED_GIT_BLOB_SHA1 = "785688868931d48845f1df47837feff7861399d7"
SHA1_RE = re.compile(r"^[0-9a-f]{40}$")
ROOT = Path(__file__).resolve().parents[2]
DEFAULT_PIN = ROOT / "data/source_plans/brussels_missing_road_source_evidence_blob.pin.json"


def _reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def git_blob_sha1(payload: bytes) -> str:
    header = f"blob {len(payload)}\0".encode("ascii")
    return hashlib.sha1(header + payload).hexdigest()


def validate_pin(pin_path: Path = DEFAULT_PIN) -> str:
    try:
        pin = json.loads(
            pin_path.read_text(encoding="utf-8"),
            object_pairs_hook=_reject_duplicate_keys,
        )
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as exc:
        raise SystemExit(f"EVIDENCE_BLOB_PIN_FAIL: cannot load pin: {exc}") from exc
    if not isinstance(pin, dict) or set(pin) != PIN_KEYS or pin.get("schema") != PIN_SCHEMA:
        raise SystemExit("EVIDENCE_BLOB_PIN_FAIL: pin schema drift")

    target_path = pin.get("target_path")
    expected = pin.get("git_blob_sha1")
    if not isinstance(target_path, str) or not target_path or Path(target_path).is_absolute():
        raise SystemExit("EVIDENCE_BLOB_PIN_FAIL: invalid target path")
    if target_path != EXPECTED_TARGET_PATH:
        raise SystemExit("EVIDENCE_BLOB_PIN_FAIL: target path contract drift")
    if not isinstance(expected, str) or SHA1_RE.fullmatch(expected) is None:
        raise SystemExit("EVIDENCE_BLOB_PIN_FAIL: invalid Git blob SHA-1")
    if expected != EXPECTED_GIT_BLOB_SHA1:
        raise SystemExit("EVIDENCE_BLOB_PIN_FAIL: Git blob pin contract drift")

    target = (ROOT / target_path).resolve()
    try:
        target.relative_to(ROOT.resolve())
    except ValueError as exc:
        raise SystemExit("EVIDENCE_BLOB_PIN_FAIL: target escapes repository root") from exc
    try:
        payload = target.read_bytes()
    except OSError as exc:
        raise SystemExit(f"EVIDENCE_BLOB_PIN_FAIL: cannot read target: {exc}") from exc

    actual = git_blob_sha1(payload)
    if actual != expected:
        raise SystemExit(
            f"EVIDENCE_BLOB_PIN_FAIL: immutable evidence Git blob drift: expected={expected} actual={actual}"
        )
    return actual


def main() -> int:
    actual = validate_pin()
    print(f"EVIDENCE_BLOB_PIN_OK: git_blob_sha1={actual}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
