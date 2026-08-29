#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

FORMAT = "grand-bruxelles-registered-cell-manifest-index-v1"
READINESS = "REGISTERED_CELL_INDEX_EVIDENCE_ONLY"


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def sha256_json(value: Any) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()


def is_sha256(value: Any) -> bool:
    text = str(value or "").lower()
    return len(text) == 64 and all(ch in "0123456789abcdef" for ch in text)


def semantic_payload(index: dict[str, Any]) -> dict[str, Any]:
    payload = dict(index)
    payload.pop("semantic_sha256", None)
    payload.pop("production_base_sha", None)
    return payload


def validate(index: dict[str, Any]) -> str:
    if index.get("schema") != FORMAT or index.get("destination_readiness") != READINESS:
        raise SystemExit("REGISTERED_CELL_INDEX_SEMANTIC_FAIL: schema/readiness drift")
    for key, value in index.items():
        if key.endswith("_authorized") and value is not False:
            raise SystemExit(f"REGISTERED_CELL_INDEX_SEMANTIC_FAIL: authorization opened: {key}")
    stored = str(index.get("semantic_sha256") or "").lower()
    if not is_sha256(stored):
        raise SystemExit("REGISTERED_CELL_INDEX_SEMANTIC_FAIL: semantic sha malformed")
    computed = sha256_json(semantic_payload(index))
    if stored != computed:
        raise SystemExit("REGISTERED_CELL_INDEX_SEMANTIC_FAIL: semantic sha drift")
    entries = index.get("entries")
    if not isinstance(entries, list) or len(entries) != int(index.get("registered_cell_count", -1)):
        raise SystemExit("REGISTERED_CELL_INDEX_SEMANTIC_FAIL: cell accounting drift")
    ids = [str(row.get("cell_id") or "") for row in entries if isinstance(row, dict)]
    if len(ids) != len(entries) or not all(ids) or ids != sorted(set(ids)):
        raise SystemExit("REGISTERED_CELL_INDEX_SEMANTIC_FAIL: cell identity drift")
    return computed


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--index", type=Path, default=Path("data/provenance/brussels_registered_cell_manifest_index.json"))
    args = parser.parse_args()
    value = json.loads(args.index.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise SystemExit("REGISTERED_CELL_INDEX_SEMANTIC_FAIL: invalid object")
    digest = validate(value)
    print(f"REGISTERED_CELL_INDEX_SEMANTIC_GREEN: cells={value['registered_cell_count']} semantic_sha256={digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
