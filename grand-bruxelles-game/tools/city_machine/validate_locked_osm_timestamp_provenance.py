#!/usr/bin/env python3
from __future__ import annotations

from datetime import datetime, timezone
import json
import re
from pathlib import Path
from typing import Any

EVIDENCE = Path("data/source_plans/brussels_missing_road_source_acquisition_evidence.lock.json")
EXPECTED_RUN = {
    "workflow": "Grand Bruxelles Missing Road Source Batch",
    "run_id": 33343196025,
    "source_pr": 1675,
    "source_head_sha": "c9606e28eae99ef9dca77be53bb4e7a83cb94e7f",
}
EXPECTED_RUN_COMPLETED_AT = datetime(2026, 8, 31, 0, 3, 39, tzinfo=timezone.utc)
LOCKED_STATUS = "ACQUIRED_ARTIFACT_LOCKED"
TIMESTAMP_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")


def reject_duplicate_object_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON object key: {key}")
        result[key] = value
    return result


def fail(message: str) -> None:
    raise SystemExit(f"LOCKED_OSM_TIMESTAMP_PROVENANCE_FAIL: {message}")


def parse_timestamp(value: Any, nis: str) -> datetime:
    if not isinstance(value, str) or TIMESTAMP_RE.fullmatch(value) is None:
        fail(f"noncanonical osm_base_timestamp for {nis}")
    try:
        parsed = datetime.fromisoformat(value[:-1] + "+00:00")
    except ValueError as exc:
        fail(f"invalid osm_base_timestamp for {nis}: {exc}")
    if parsed.utcoffset() != timezone.utc.utcoffset(parsed):
        fail(f"non-UTC osm_base_timestamp for {nis}")
    return parsed


def validate_run_provenance(value: Any) -> None:
    if not isinstance(value, dict) or set(value) != set(EXPECTED_RUN):
        fail("acquisition run schema drift")
    for key, expected in EXPECTED_RUN.items():
        actual = value.get(key)
        if key in {"run_id", "source_pr"} and isinstance(actual, bool):
            fail(f"acquisition run provenance drift for {key}")
        if actual != expected:
            fail(f"acquisition run provenance drift for {key}")


def main() -> int:
    try:
        evidence = json.loads(
            EVIDENCE.read_text(encoding="utf-8"),
            object_pairs_hook=reject_duplicate_object_keys,
        )
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as exc:
        fail(f"cannot load locked evidence: {exc}")

    if not isinstance(evidence, dict):
        fail("locked evidence must be an object")
    validate_run_provenance(evidence.get("acquisition_run"))

    rows = evidence.get("successful_acquisitions")
    if not isinstance(rows, list) or not rows:
        fail("successful_acquisitions must be a non-empty list")

    checked = 0
    for row in rows:
        if not isinstance(row, dict):
            fail("locked acquisition row must be an object")
        nis = row.get("niscode")
        if not isinstance(nis, str) or not nis:
            fail("locked acquisition row missing niscode")
        if row.get("status") != LOCKED_STATUS:
            fail(f"unexpected source status for {nis}")
        timestamp = parse_timestamp(row.get("osm_base_timestamp"), nis)
        if timestamp > EXPECTED_RUN_COMPLETED_AT:
            fail(
                f"osm_base_timestamp for {nis} is later than pinned run completion "
                f"{EXPECTED_RUN_COMPLETED_AT.isoformat().replace('+00:00', 'Z')}"
            )
        checked += 1

    print(
        "LOCKED_OSM_TIMESTAMP_PROVENANCE_GREEN: "
        f"run_id={EXPECTED_RUN['run_id']} locked_rows={checked} "
        f"max_timestamp={EXPECTED_RUN_COMPLETED_AT.isoformat().replace('+00:00', 'Z')}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
