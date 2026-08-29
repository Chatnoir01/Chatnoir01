#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from typing import Any

SCHEMA = "grand-bruxelles-registered-cell-manifest-index-v1"
TARGET_CRS = "EPSG:31370"
CELL_SIZE_M = 500


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def semantic_payload(registry: dict[str, Any]) -> dict[str, Any]:
    return {k: v for k, v in registry.items() if k not in {"semantic_sha256", "production_base_sha"}}


def semantic_sha256(registry: dict[str, Any]) -> str:
    return hashlib.sha256(canonical_json(semantic_payload(registry)).encode("utf-8")).hexdigest()


def _is_lower_hex(value: Any, length: int) -> bool:
    return isinstance(value, str) and len(value) == length and all(ch in "0123456789abcdef" for ch in value)


def _require_int(value: Any, label: str, *, minimum: int | None = None) -> int:
    if type(value) is not int:
        raise SystemExit(f"REGISTERED_CELL_INDEX_FAIL: {label} JSON type drift")
    if minimum is not None and value < minimum:
        raise SystemExit(f"REGISTERED_CELL_INDEX_FAIL: {label} value drift")
    return value


def _require_integral_number(value: Any, label: str) -> int:
    if type(value) is int:
        return value
    if type(value) is float:
        if not math.isfinite(value):
            raise SystemExit(f"REGISTERED_CELL_INDEX_FAIL: {label} non-finite drift")
        if not value.is_integer():
            raise SystemExit(f"REGISTERED_CELL_INDEX_FAIL: {label} integral-coordinate drift")
        return int(value)
    raise SystemExit(f"REGISTERED_CELL_INDEX_FAIL: {label} JSON type drift")


def _validate_entry_identity(row: Any) -> None:
    if not isinstance(row, dict):
        raise SystemExit("REGISTERED_CELL_INDEX_FAIL: entry object drift")
    cell_id = row.get("cell_id")
    if not isinstance(cell_id, str) or not cell_id:
        raise SystemExit("REGISTERED_CELL_INDEX_FAIL: cell identity drift")
    if row.get("crs") != TARGET_CRS:
        raise SystemExit("REGISTERED_CELL_INDEX_FAIL: cell CRS drift")
    bbox = row.get("bbox")
    if not isinstance(bbox, list) or len(bbox) != 4:
        raise SystemExit("REGISTERED_CELL_INDEX_FAIL: registered cell bbox shape drift")
    east, north, east_max, north_max = [
        _require_integral_number(value, f"registered cell bbox[{index}]")
        for index, value in enumerate(bbox)
    ]
    if east % CELL_SIZE_M != 0 or north % CELL_SIZE_M != 0:
        raise SystemExit("REGISTERED_CELL_INDEX_FAIL: registered cell bbox grid alignment drift")
    if [east, north, east + CELL_SIZE_M, north + CELL_SIZE_M] != [east, north, east_max, north_max]:
        raise SystemExit("REGISTERED_CELL_INDEX_FAIL: registered cell bbox identity drift")
    if cell_id != f"bxl-e{east}-n{north}-s{CELL_SIZE_M}":
        raise SystemExit("REGISTERED_CELL_INDEX_FAIL: registered cell id/bbox identity drift")


def validate_registry(registry: dict[str, Any]) -> None:
    if registry.get("schema") != SCHEMA:
        raise SystemExit("REGISTERED_CELL_INDEX_FAIL: schema drift")
    stored = registry.get("semantic_sha256")
    if not _is_lower_hex(stored, 64):
        raise SystemExit("REGISTERED_CELL_INDEX_FAIL: semantic sha format drift")
    production_base = registry.get("production_base_sha")
    if not _is_lower_hex(production_base, 40):
        raise SystemExit("REGISTERED_CELL_INDEX_FAIL: production base sha format drift")
    entries = registry.get("entries")
    if not isinstance(entries, list):
        raise SystemExit("REGISTERED_CELL_INDEX_FAIL: entries drift")
    declared_count = _require_int(registry.get("registered_cell_count"), "registered_cell_count", minimum=0)
    if len(entries) != declared_count:
        raise SystemExit("REGISTERED_CELL_INDEX_FAIL: registered cell accounting drift")
    seen: set[str] = set()
    for row in entries:
        _validate_entry_identity(row)
        cell_id = row["cell_id"]
        if cell_id in seen:
            raise SystemExit("REGISTERED_CELL_INDEX_FAIL: duplicate registered cell")
        seen.add(cell_id)
    expected = semantic_sha256(registry)
    if stored != expected:
        raise SystemExit("REGISTERED_CELL_INDEX_FAIL: semantic sha drift")


def load_registry(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise SystemExit(f"REGISTERED_CELL_INDEX_FAIL: invalid JSON {path}") from exc
    if not isinstance(value, dict):
        raise SystemExit(f"REGISTERED_CELL_INDEX_FAIL: invalid object {path}")
    return value


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--registry", type=Path, default=Path("data/provenance/brussels_registered_cell_manifest_index.json"))
    args = parser.parse_args()
    registry = load_registry(args.registry)
    validate_registry(registry)
    print(f"REGISTERED_CELL_INDEX_SEMANTIC_GREEN entries={len(registry.get('entries') or [])} sha256={registry['semantic_sha256']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())