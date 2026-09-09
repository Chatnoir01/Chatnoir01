from __future__ import annotations

import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE_PATH = ROOT / "data/source_plans/brussels_spatial_crosswalk_origin_evidence.lock.json"
EXPECTED_SCHEMA = "grand-bruxelles-spatial-crosswalk-origin-evidence-v1"
EXPECTED_MEASUREMENT_SCHEMA = "grand-bruxelles-road-registered-cell-overlap-measurement-v2"
EXPECTED_MEASUREMENT_SEMANTIC_SHA256 = "2d84dbc4d6a80e10f093f8135e2fba6e9b55b813eb42c2588be7566ae6c16f95"
EXPECTED_TOP_KEYS = {"schema", "source_owner", "measured_contract", "authorization", "scope_note"}


def _reject_duplicate_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    payload: dict[str, Any] = {}
    for key, value in pairs:
        if key in payload:
            raise ValueError(f"duplicate JSON key: {key}")
        payload[key] = value
    return payload


def _load_strict(path: Path) -> Any:
    try:
        return json.loads(path.read_bytes().decode("utf-8"), object_pairs_hook=_reject_duplicate_pairs)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError("origin evidence is not valid UTF-8 JSON") from exc


def validate() -> None:
    evidence = _load_strict(EVIDENCE_PATH)
    if not isinstance(evidence, dict) or set(evidence) != EXPECTED_TOP_KEYS:
        raise ValueError("origin evidence schema drift")
    if evidence["schema"] != EXPECTED_SCHEMA:
        raise ValueError("origin evidence schema drift")
    measured = evidence["measured_contract"]
    if not isinstance(measured, dict):
        raise ValueError("origin evidence measured_contract missing")
    if measured.get("schema") != EXPECTED_MEASUREMENT_SCHEMA:
        raise ValueError("origin evidence measured contract identity drift")
    if measured.get("semantic_sha256") != EXPECTED_MEASUREMENT_SEMANTIC_SHA256:
        raise ValueError("measurement semantic immutable identity drift")


def main() -> int:
    validate()
    print("spatial crosswalk origin measurement semantic identity: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
