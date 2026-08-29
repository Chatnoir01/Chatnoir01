#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

SCHEMA = "grand-bruxelles-registered-cell-manifest-index-v1"


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def semantic_payload(registry: dict[str, Any]) -> dict[str, Any]:
    return {k: v for k, v in registry.items() if k not in {"semantic_sha256", "production_base_sha"}}


def semantic_sha256(registry: dict[str, Any]) -> str:
    return hashlib.sha256(canonical_json(semantic_payload(registry)).encode("utf-8")).hexdigest()


def _is_lower_hex(value: Any, length: int) -> bool:
    return isinstance(value, str) and len(value) == length and all(ch in "0123456789abcdef" for ch in value)


def validate_registry(registry: dict[str, Any]) -> None:
    if registry.get("schema") != SCHEMA:
        raise SystemExit("REGISTERED_CELL_INDEX_FAIL: schema drift")
    stored = registry.get("semantic_sha256")
    if not _is_lower_hex(stored, 64):
        raise SystemExit("REGISTERED_CELL_INDEX_FAIL: semantic sha format drift")
    production_base = registry.get("production_base_sha")
    if not _is_lower_hex(production_base, 40):
        raise SystemExit("REGISTERED_CELL_INDEX_FAIL: production base sha format drift")
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
