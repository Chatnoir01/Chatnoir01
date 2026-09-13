#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path, PurePosixPath
from typing import Any

EXPECTED_SCHEMA = "grand-bruxelles-road-destination-readiness-catalog-v1"


def _strict_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    out: dict[str, Any] = {}
    for key, value in pairs:
        if key in out:
            raise ValueError(f"duplicate JSON key: {key}")
        out[key] = value
    return out


def _finite_float(value: str) -> float:
    parsed = float(value)
    if not math.isfinite(parsed):
        raise ValueError(f"non-finite JSON number: {value}")
    return parsed


def load_catalog(path: Path) -> dict[str, Any]:
    parsed = json.loads(
        path.read_text(encoding="utf-8"),
        object_pairs_hook=_strict_object,
        parse_float=_finite_float,
        parse_constant=lambda value: (_ for _ in ()).throw(ValueError(f"non-finite JSON number: {value}")),
    )
    if not isinstance(parsed, dict):
        raise ValueError("catalog root must be an object")
    return parsed


def _canonical_nonempty(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value:
        raise ValueError(f"{label} must be a non-empty string")
    if value != value.strip():
        raise ValueError(f"{label} must not contain leading/trailing whitespace")
    if any(ord(char) < 32 or ord(char) == 127 for char in value):
        raise ValueError(f"{label} must not contain control characters")
    return value


def _canonical_source_path(value: Any, label: str) -> str:
    path = _canonical_nonempty(value, label)
    if "\\" in path:
        raise ValueError(f"{label} must use canonical POSIX separators")
    pure = PurePosixPath(path)
    if pure.is_absolute() or any(part in {".", ".."} for part in pure.parts):
        raise ValueError(f"{label} must be a relative traversal-free path")
    if str(pure) != path:
        raise ValueError(f"{label} must be in canonical POSIX form")
    return path


def validate(catalog: dict[str, Any]) -> tuple[int, int]:
    if catalog.get("schema") != EXPECTED_SCHEMA:
        raise ValueError("unexpected catalog schema")
    rows = catalog.get("destinations")
    if not isinstance(rows, list) or not rows:
        raise ValueError("catalog destinations missing")

    cell_ids: set[str] = set()
    source_paths: set[str] = set()
    for index, row in enumerate(rows):
        if not isinstance(row, dict):
            raise ValueError(f"destination row {index} must be an object")
        cell_ids.add(_canonical_nonempty(row.get("cell_id"), f"destination row {index}.cell_id"))
        source_paths.add(_canonical_source_path(row.get("source_path"), f"destination row {index}.source_path"))

    if type(catalog.get("mapped_cell_count")) is not int or catalog["mapped_cell_count"] != len(cell_ids):
        raise ValueError("mapped_cell_count does not match canonical distinct cell identities")
    if type(catalog.get("source_document_count")) is not int or catalog["source_document_count"] != len(source_paths):
        raise ValueError("source_document_count does not match canonical distinct source paths")
    return len(cell_ids), len(source_paths)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("catalog", type=Path)
    args = parser.parse_args()
    catalog = load_catalog(args.catalog)
    cells, sources = validate(catalog)
    print(
        "ROAD_DESTINATION_READINESS_CANONICAL_AGGREGATE_IDENTITY_OK "
        f"mapped_cells={cells} source_documents={sources} "
        "whitespace_aliases_rejected=true control_aliases_rejected=true "
        "source_path_aliases_rejected=true canonical_aggregate_identity=true"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
